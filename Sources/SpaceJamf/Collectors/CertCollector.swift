import Foundation

struct CertCollector: CollectorProtocol {
    let area: DiagnosticArea = .certs
    let requiresElevation: Bool = false

    // Upper limit on per-cert openssl invocations. Enterprise machines rarely have
    // more than 20 relevant certs in System.keychain, and inspecting them all would
    // exceed the 8 KB per-section prompt cap anyway.
    private let maxCertsToInspect = 20

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        // ── Export all certs from System.keychain as PEM ──────────────────────
        let findCert = await Shell.run(
            "/usr/bin/security",
            args: ["find-certificate", "-a", "-p", "/Library/Keychains/System.keychain"],
            timeout: 15
        )
        exitCodes["security-find-certificate"] = findCert.exitCode

        guard findCert.exitCode == 0, !findCert.stdout.isEmpty else {
            output = "=== Certificate Collection ===\n"
            output += "No certificates found or access denied to System.keychain.\n"
            if !findCert.stderr.isEmpty { output += "[stderr]: \(findCert.stderr)\n" }
            return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
        }

        let (pems, foundMalformedBlock) = extractPEMs(from: findCert.stdout)
        output += "=== Certificate Summary (\(pems.count) cert(s) in System.keychain) ===\n\n"

        // Pre-flight check for openssl — absent on non-standard macOS installs.
        // Emit a clear message rather than per-cert launch-failure lines.
        guard FileManager.default.fileExists(atPath: "/usr/bin/openssl") else {
            output += "(openssl not found at /usr/bin/openssl — per-cert inspection skipped)\n"
            return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
        }

        // Inspect certs in bounded batches of 4 to avoid an unbounded burst of
        // simultaneous openssl subprocesses on a loaded machine.
        var certInfos: [(index: Int, result: ShellResult)] = []
        let certsToInspect = Array(pems.prefix(maxCertsToInspect))
        let batchSize = 4
        for batchStart in stride(from: 0, to: certsToInspect.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, certsToInspect.count)
            let batch = certsToInspect[batchStart..<batchEnd]
            await withTaskGroup(of: (Int, ShellResult).self) { group in
                for (localIdx, pem) in batch.enumerated() {
                    let globalIdx = batchStart + localIdx
                    group.addTask {
                        let result = await Shell.run(
                            "/usr/bin/openssl",
                            args: ["x509", "-noout", "-subject", "-issuer", "-dates"],
                            stdin: Data(pem.utf8),
                            timeout: 5
                        )
                        return (globalIdx, result)
                    }
                }
                for await (index, result) in group {
                    certInfos.append((index: index, result: result))
                }
            }
        }
        certInfos.sort { $0.index < $1.index }

        for (index, certInfo) in certInfos {
            output += "--- Certificate \(index + 1) ---\n"
            output += certInfo.stdout.isEmpty ? "(no output)\n" : certInfo.stdout
            if !certInfo.stderr.isEmpty { output += "[stderr]: \(certInfo.stderr)\n" }
            exitCodes["openssl-cert-\(index + 1)"] = certInfo.exitCode
        }

        if pems.count > maxCertsToInspect {
            output += "\n… \(pems.count - maxCertsToInspect) additional certificate(s) not shown.\n"
        }

        if foundMalformedBlock {
            output += "\nWarning: one or more certificate blocks were malformed (missing END CERTIFICATE marker).\n"
        }

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }

    /// Exposed as internal for test access (TS-6).
    func extractPEMs(from pemChain: String) -> (pems: [String], foundMalformedBlock: Bool) {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end   = "-----END CERTIFICATE-----"
        var pems: [String] = []
        var current: [String] = []
        var inCert = false
        var foundMalformedBlock = false

        for line in pemChain.components(separatedBy: .newlines) {
            // CC1: Trim whitespace before comparing so trailing CR, space, or tab
            // from some security(1) output variants does not silently skip the block.
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine == begin {
                if inCert {
                    // A new BEGIN encountered while already inside a block; the prior
                    // block is incomplete — mark as malformed and start fresh.
                    foundMalformedBlock = true
                }
                inCert = true
                current = [line]
            } else if trimmedLine == end {
                current.append(line)
                pems.append(current.joined(separator: "\n"))
                inCert = false
                current = []
            } else if inCert {
                current.append(line)
            }
        }
        // foundMalformedBlock covers an unterminated block (inCert still true at EOF)
        // as well as nested BEGIN blocks caught above.
        return (pems, foundMalformedBlock || inCert)
    }
}
