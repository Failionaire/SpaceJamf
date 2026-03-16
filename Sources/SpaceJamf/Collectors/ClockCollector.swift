import Foundation

struct ClockCollector: CollectorProtocol {
    let area: DiagnosticArea = .clock
    let requiresElevation: Bool = false

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        // Run all three concurrently — they are fully independent
        async let sntpTask        = Shell.run("/usr/bin/sntp", args: ["-t", "5", "time.apple.com"])
        async let systemsetupTask = Shell.run("/usr/sbin/systemsetup", args: ["-getusingnetworktime"])
        async let dateTask        = Shell.run("/bin/date", args: ["+%s"])
        let (sntp, systemsetup, dateResult) = await (sntpTask, systemsetupTask, dateTask)

        // ── sntp ─────────────────────────────────────────────────────────────
        output += "=== sntp -t 5 time.apple.com ===\n\(sntp.stdout)"
        if !sntp.stderr.isEmpty { output += "[stderr]: \(sntp.stderr)\n" }
        exitCodes["sntp"] = sntp.exitCode

        // ── systemsetup -getusingnetworktime ─────────────────────────────────
        output += "\n=== systemsetup -getusingnetworktime ===\n\(systemsetup.stdout)"
        if !systemsetup.stderr.isEmpty { output += "[stderr]: \(systemsetup.stderr)\n" }
        exitCodes["systemsetup-networktime"] = systemsetup.exitCode

        // ── Local clock epoch ─────────────────────────────────────────────────
        let epochStr = dateResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let epoch = Int(epochStr) ?? 0
        let humanDate = DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: TimeInterval(epoch)),
            dateStyle: .full,
            timeStyle: .long
        )
        output += "\n=== System Clock ===\nEpoch:  \(epoch)\nLocal:  \(humanDate)\n"
        exitCodes["date"] = dateResult.exitCode

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }
}
