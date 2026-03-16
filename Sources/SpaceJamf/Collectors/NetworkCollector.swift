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
            let hostResult = await Shell.run("/usr/bin/host", args: [domain])
            output += "=== DNS: host \(domain) ===\n\(hostResult.stdout)"
            if !hostResult.stderr.isEmpty { output += "[stderr]: \(hostResult.stderr)\n" }
            exitCodes["host-ad"] = hostResult.exitCode
        } else {
            output += "=== DNS ===\nAD domain not detected; DNS lookup skipped.\n"
        }

        // ── JSS reachability ─────────────────────────────────────────────────

        if let jss {
            let curlResult = await Shell.run(
                "/usr/bin/curl",
                args: [
                    "-s", "-o", "/dev/null",
                    "--connect-timeout", "10",
                    "-w", "%{http_code}",
                    jss
                ]
            )
            output += "\n=== JSS Reachability: \(jss) ===\n"
            output += "HTTP status: \(curlResult.stdout)\n"
            if !curlResult.stderr.isEmpty { output += "[stderr]: \(curlResult.stderr)\n" }
            exitCodes["curl-jss"] = curlResult.exitCode
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
            args: ["read", "/Library/Preferences/com.jamfsoftware.jamf", "jss_url"]
        )
        guard result.exitCode == 0 else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }
}
