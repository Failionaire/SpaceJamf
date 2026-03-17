import Foundation

struct ClockCollector: CollectorProtocol {
    let area: DiagnosticArea = .clock
    let requiresElevation: Bool = false

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        // CK1: Trim the env var value and fall back to the default if blank/whitespace-only.
        // ntpServer comes from a user-controlled env var. Shell.run passes it as a
        // process argument (not a shell string), so shell injection is not possible.
        // The value appears verbatim in diagnostic output and is scrubbed by Scrubber.
        let rawNTP   = ProcessInfo.processInfo.environment["SPACEJAMF_NTP_SERVER"] ?? ""
        let ntpServer = rawNTP.trimmingCharacters(in: .whitespaces).isEmpty
            ? "time.apple.com"
            : rawNTP.trimmingCharacters(in: .whitespaces)
        async let sntpTask        = Shell.run("/usr/bin/sntp",         args: ["-t", "5", ntpServer], timeout: 10)
        async let systemsetupTask = Shell.run("/usr/sbin/systemsetup", args: ["-getusingnetworktime"],  timeout: 10)
        async let dateTask        = Shell.run("/bin/date",             args: ["+%s"])
        let (sntp, systemsetup, dateResult) = await (sntpTask, systemsetupTask, dateTask)

        // ── sntp ─────────────────────────────────────────────────────────────
        output += "=== sntp -t 5 \(ntpServer) ===\n\(sntp.stdout)"
        if !sntp.stderr.isEmpty { output += "[stderr]: \(sntp.stderr)\n" }
        exitCodes["sntp"] = sntp.exitCode

        // ── systemsetup -getusingnetworktime ─────────────────────────────────
        output += "\n=== systemsetup -getusingnetworktime ===\n\(systemsetup.stdout)"
        if !systemsetup.stderr.isEmpty { output += "[stderr]: \(systemsetup.stderr)\n" }
        exitCodes["systemsetup-networktime"] = systemsetup.exitCode

        // ── Local clock epoch ─────────────────────────────────────────────────
        let epochStr = dateResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // CK-1: Use if-let rather than a pre-check + force-unwrap for clarity and safety.
        if dateResult.exitCode == 0, let epoch = Int(epochStr) {
            let humanDate = DateFormatter.localizedString(
                from: Date(timeIntervalSince1970: TimeInterval(epoch)),
                dateStyle: .full,
                timeStyle: .long
            )
            output += "\n=== System Clock ===\nEpoch:  \(epoch)\nLocal:  \(humanDate)\n"
        } else {
            output += "\n=== System Clock ===\n(unavailable)\n"
        }
        exitCodes["date"] = dateResult.exitCode

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }
}
