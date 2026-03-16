import Foundation

struct ADCollector: CollectorProtocol {
    let area: DiagnosticArea = .ad
    let requiresElevation: Bool = true

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        // Run dsconfigad, klist, and hostname concurrently (dscl depends on hostname)
        async let dsconfigadTask = Shell.run("/usr/sbin/dsconfigad", args: ["-show"], timeout: 15)
        async let klistTask      = Shell.run("/usr/bin/klist",       args: ["-v"],    timeout: 5)
        async let hostnameTask   = Shell.run("/bin/hostname",         args: [],        timeout: 5)
        let (dsconfigad, klist, hostnameResult) = await (dsconfigadTask, klistTask, hostnameTask)

        // ── dsconfigad -show ─────────────────────────────────────────────────
        output += "=== dsconfigad -show ===\n\(dsconfigad.stdout)"
        if !dsconfigad.stderr.isEmpty { output += "[stderr]: \(dsconfigad.stderr)\n" }
        exitCodes["dsconfigad"] = dsconfigad.exitCode

        // ── klist -v ─────────────────────────────────────────────────────────
        output += "\n=== klist -v ===\n\(klist.stdout)"
        if !klist.stderr.isEmpty { output += "[stderr]: \(klist.stderr)\n" }
        exitCodes["klist"] = klist.exitCode

        // ── dscl . -read /Computers/<hostname> ───────────────────────────────
        let hostname = hostnameResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)        guard !hostname.isEmpty else {
            output += "\n=== dscl lookup ===\nhostname unavailable; skipping dscl lookup.\n"
            exitCodes["dscl"] = -1
            return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
        }        let dscl = await Shell.run(
            "/usr/bin/dscl",
            args: [".", "-read", "/Computers/\(hostname)"],
            timeout: 15
        )
        output += "\n=== dscl . -read /Computers/\(hostname) ===\n\(dscl.stdout)"
        if !dscl.stderr.isEmpty { output += "[stderr]: \(dscl.stderr)\n" }
        exitCodes["dscl"] = dscl.exitCode

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }
}
