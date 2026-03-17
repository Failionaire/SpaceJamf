import Foundation

struct ADCollector: CollectorProtocol {
    let area: DiagnosticArea = .ad
    let requiresElevation: Bool = true

    /// Override hostname for testing (auto-resolved from `/bin/hostname` when nil).
    /// AD3: Injectable property allows unit tests to bypass real system calls,
    /// matching the pattern used by NetworkCollector.adDomain / jssURL.
    var hostname: String?

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        // Run dsconfigad and klist concurrently — they are fully independent.
        async let dsconfigadTask = Shell.run("/usr/sbin/dsconfigad", args: ["-show"], timeout: 15)
        async let klistTask      = Shell.run("/usr/bin/klist",       args: ["-v"],    timeout: 5)
        let (dsconfigad, klist) = await (dsconfigadTask, klistTask)

        // ── dsconfigad -show ─────────────────────────────────────────────────
        output += "=== dsconfigad -show ===\n\(dsconfigad.stdout)"
        if !dsconfigad.stderr.isEmpty { output += "[stderr]: \(dsconfigad.stderr)\n" }
        exitCodes["dsconfigad"] = dsconfigad.exitCode

        // ── klist -v ─────────────────────────────────────────────────────────
        output += "\n=== klist -v ===\n\(klist.stdout)"
        if !klist.stderr.isEmpty { output += "[stderr]: \(klist.stderr)\n" }
        exitCodes["klist"] = klist.exitCode

        // ── dscl . -read /Computers/<hostname> ───────────────────────────────
        // Use the injected hostname when set; otherwise resolve from /bin/hostname.
        // AD3: hostname is resolved after the concurrent batch above because dscl
        // depends on it. /bin/hostname is near-instant, so serialising it is not
        // worth the complexity of a three-way async let.
        let resolvedHostname: String
        if let injected = hostname {
            resolvedHostname = injected
        } else {
            let hostnameResult = await Shell.run("/bin/hostname", args: [], timeout: 5)
            resolvedHostname = hostnameResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !resolvedHostname.isEmpty else {
            output += "\n=== dscl lookup ===\nhostname unavailable; skipping dscl lookup.\n"
            exitCodes["dscl"] = -1
            return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
        }
        // dscl depends on hostname, so it runs after the concurrent batch above.
        let dscl = await Shell.run(
            "/usr/bin/dscl",
            args: [".", "-read", "/Computers/\(resolvedHostname)"],
            timeout: 15
        )
        // AD2: Header format mirrors JamfCollector section headers; keep in sync if changed.
        output += "\n=== dscl . -read /Computers/\(resolvedHostname) ===\n\(dscl.stdout)"
        if !dscl.stderr.isEmpty { output += "[stderr]: \(dscl.stderr)\n" }
        exitCodes["dscl"] = dscl.exitCode

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }
}
