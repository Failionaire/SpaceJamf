import Foundation

struct JamfCollector: CollectorProtocol {
    let area: DiagnosticArea = .jamf
    let requiresElevation: Bool = false

    /// Path to the jamf binary. Injectable via the designated initialiser for unit tests.
    let jamfPath: String

    /// - Parameter jamfPath: Path to the jamf binary (default: `/usr/local/bin/jamf`).
    init(jamfPath: String = "/usr/local/bin/jamf") {
        self.jamfPath = jamfPath
    }

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        guard FileManager.default.fileExists(atPath: jamfPath) else {
            output = """
            Jamf binary not found at \(jamfPath).
            This Mac may not be enrolled in Jamf Pro, or the binary is in a non-standard location.
            """
            exitCodes["jamf"] = -1
            return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
        }

        // Run all Jamf commands concurrently — they are fully independent
        async let jamfVersionTask    = Shell.run(jamfPath, args: ["version"],                    timeout: 15)
        async let checkJSSTask       = Shell.run(jamfPath, args: ["checkJSSConnection"],         timeout: 15)
        async let profilesListTask   = Shell.run("/usr/bin/profiles", args: ["list"],           timeout: 15)
        async let profilesEnrollTask = Shell.run("/usr/bin/profiles", args: ["show", "-type", "enrollment"], timeout: 15)
        let (jamfVersion, checkJSS, profilesList, profilesEnrollment) =
            await (jamfVersionTask, checkJSSTask, profilesListTask, profilesEnrollTask)

        // ── jamf version ─────────────────────────────────────────────────────
        output += "=== jamf version ===\n\(jamfVersion.stdout)"
        if !jamfVersion.stderr.isEmpty { output += "[stderr]: \(jamfVersion.stderr)\n" }
        exitCodes["jamf-version"] = jamfVersion.exitCode

        // ── jamf checkJSSConnection ───────────────────────────────────────────
        output += "\n=== jamf checkJSSConnection ===\n\(checkJSS.stdout)"
        if !checkJSS.stderr.isEmpty { output += "[stderr]: \(checkJSS.stderr)\n" }
        exitCodes["jamf-checkJSSConnection"] = checkJSS.exitCode

        // ── profiles list ─────────────────────────────────────────────────────
        output += "\n=== profiles list ===\n\(profilesList.stdout)"
        if !profilesList.stderr.isEmpty { output += "[stderr]: \(profilesList.stderr)\n" }
        exitCodes["profiles-list"] = profilesList.exitCode

        // ── profiles show -type enrollment ────────────────────────────────────
        // JA-2: `profiles show -type enrollment` returns richer MDM payload detail
        // than `profiles list` alone (e.g. PayloadUUID, server URL, managed state).
        output += "\n=== profiles show -type enrollment ===\n\(profilesEnrollment.stdout)"
        if !profilesEnrollment.stderr.isEmpty {
            output += "[stderr]: \(profilesEnrollment.stderr)\n"
        }
        exitCodes["profiles-enrollment"] = profilesEnrollment.exitCode

        // JA-3: The JSS URL appears in checkJSSConnection output and may include the
        // hostname or IP. Scrubber.scrub() will redact IP literals; hostname scrubbing
        // (if required) must be configured separately via the SPACEJAMF_SCRUB_WORDS env var.
        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }
}
