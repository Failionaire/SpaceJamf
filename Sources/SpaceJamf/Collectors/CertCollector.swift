import Foundation

struct CertCollector: CollectorProtocol {
    let area: DiagnosticArea = .certs
    let requiresElevation: Bool = false

    /// Maximum number of certs to inspect individually (avoids very long output).
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

        let (pems, hadMalformed) = extractPEMs(from: findCert.stdout)
        output += "=== Certificate Summary (\(pems.count) cert(s) in System.keychain) ===\n\n"

        // Inspect all certs concurrently and reassemble in original order
        var certInfos: [(index: Int, result: ShellResult)] = []
        await withTaskGroup(of: (Int, ShellResult).self) { group in
            for (index, pem) in pems.prefix(maxCertsToInspect).enumerated() {
                group.addTask {
                    let result = await Shell.run(
                        "/usr/bin/openssl",
                        args: ["x509", "-noout", "-subject", "-issuer", "-dates"],
                        stdin: Data(pem.utf8),
                        timeout: 5
                    )
                    return (index, result)
                }
            }
            for await (index, result) in group {
                certInfos.append((index: index, result: result))
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

        if hadMalformed {
            output += "\nWarning: one or more certificate blocks were malformed (missing END CERTIFICATE marker).\n"
        }

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }

    private func extractPEMs(from pemChain: String) -> (pems: [String], hadMalformed: Bool) {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end   = "-----END CERTIFICATE-----"
        var pems: [String] = []
        var current: [String] = []
        var inCert = false

        for line in pemChain.components(separatedBy: .newlines) {
            if line == begin {
                inCert = true
                current = [line]
            } else if line == end {
                current.append(line)
                pems.append(current.joined(separator: "\n"))
                inCert = false
                current = []
            } else if inCert {
                current.append(line)
            }
        }
        return (pems, inCert)
    }
}
