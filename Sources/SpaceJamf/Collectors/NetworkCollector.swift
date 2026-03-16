import Foundation

struct NetworkCollector: CollectorProtocol {
    let area: DiagnosticArea = .network
    let requiresElevation: Bool = false

    /// Override AD domain for testing (auto-discovered from dsconfigad when nil).
    var adDomain: String?
    /// Override JSS URL for testing (auto-discovered from Jamf prefs when nil).
    var jssURL: String?

    func collect() async -> DiagnosticResult {
        var output = ""
        var exitCodes: [String: Int32] = [:]

        // Discover AD domain and JSS URL concurrently
        async let domainDiscovery = discoverADDomain()
        async let jssDiscovery    = discoverJSSURL()
        let (discoveredDomain, discoveredJSS) = await (domainDiscovery, jssDiscovery)

        let domain = adDomain ?? discoveredDomain
        let jss    = jssURL   ?? discoveredJSS

        // ── DNS: AD domain ────────────────────────────────────────────────────
        if let domain {
            let hostResult = await Shell.run("/usr/bin/host", args: [domain], timeout: 15)
            output += "=== DNS: host \(domain) ===\n\(hostResult.stdout)"
            if !hostResult.stderr.isEmpty { output += "[stderr]: \(hostResult.stderr)\n" }
            exitCodes["host-ad"] = hostResult.exitCode
        } else {
            output += "=== DNS ===\nAD domain not detected; DNS lookup skipped.\n"
        }

        // ── JSS reachability ─────────────────────────────────────────────────

        if let jss, isAllowedURL(jss) {
            let curlResult = await Shell.run(
                "/usr/bin/curl",
                args: [
                    "-s", "-o", "/dev/null",
                    "--connect-timeout", "10",
                    "--max-time", "15",
                    "-w", "%{http_code}",
                    jss
                ],
                timeout: 20 // hard kill if curl somehow ignores --max-time
            )
            output += "\n=== JSS Reachability: \(jss) ===\n"
            output += "HTTP status: \(curlResult.stdout)\n"
            if !curlResult.stderr.isEmpty { output += "[stderr]: \(curlResult.stderr)\n" }
            exitCodes["curl-jss"] = curlResult.exitCode
        } else if let jss {
            output += "\n=== JSS Reachability: \(jss) ===\nSkipped — URL scheme is not http/https.\n"
        } else {
            output += "\n=== JSS Reachability ===\nJSS URL not detected; reachability check skipped.\n"
        }

        return DiagnosticResult(area: area, rawOutput: output, exitCodes: exitCodes)
    }

    // MARK: - Discovery helpers

    private func discoverADDomain() async -> String? {
        let result = await Shell.run("/usr/sbin/dsconfigad", args: ["-show"], timeout: 15)
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("active directory domain") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    private func discoverJSSURL() async -> String? {
        let result = await Shell.run(
            "/usr/bin/defaults",
            args: ["read", "/Library/Preferences/com.jamfsoftware.jamf", "jss_url"],
            timeout: 10 // cfprefsd can stall on broken MDM enrolments
        )
        guard result.exitCode == 0 else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    /// Returns true only for http/https URLs, preventing file:// and other schemes
    /// from being passed to curl (M-5).
    private func isAllowedURL(_ string: String) -> Bool {
        guard let u = URL(string: string) else { return false }
        return u.scheme == "https" || u.scheme == "http"
    }
}
