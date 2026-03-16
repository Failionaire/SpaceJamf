import Foundation

struct JamfCollector: CollectorProtocol {
    let area: DiagnosticArea = .jamf
    let requiresElevation: Bool = false

    /// Allows overriding the path for unit tests.
    var jamfPath: String = "/usr/local/bin/jamf"

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
        async let jamfVersionTask    = Shell.run(jamfPath, args: ["version"])
        async let checkJSSTask       = Shell.run(jamfPath, args: ["checkJSSConnection"])
        async let profilesListTask   = Shell.run("/usr/bin/profiles", args: ["list"])
        async let profilesEnrollTask = Shell.run("/usr/bin/profiles", args: ["show", "-type", "enrollment"])
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
        output += "\n=== profiles show -type enrollment ===\n\(profilesEnrollment.stdout)"
        if !profilesEnrollment.stderr.isEmpty {
            output += "[stderr]: \(profilesEnrollment.stderr)\n"
        }
        exitCodes["profiles-enrollment"] = profilesEnrollment.exitCode

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }
}
