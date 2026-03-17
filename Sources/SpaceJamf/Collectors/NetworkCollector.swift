import Foundation

struct NetworkCollector: CollectorProtocol {
    let area: DiagnosticArea = .network
    let requiresElevation: Bool = false

    /// Override AD domain for testing (auto-discovered from dsconfigad when nil).
    /// NW-4: Injectable property allows unit tests to bypass real network calls.
    var adDomain: String?
    /// Override JSS URL for testing (auto-discovered from Jamf prefs when nil).
    /// NW-4: Injectable property allows unit tests to bypass real network calls.
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

        // NW-3: URLSession is avoided here because curl's --connect-timeout / --max-time
        // flags are more portable and familiar to sysadmins reading the raw output.
        // The URL is validated by isAllowedURL() before being passed to curl.
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

    // NW-1: dsconfigad -show is also called in ADCollector, but NetworkCollector
    // keeps its own independent invocation so the two collectors remain fully
    // decoupled and can run concurrently without shared mutable state.
    private func discoverADDomain() async -> String? {
        let result = await Shell.run("/usr/sbin/dsconfigad", args: ["-show"], timeout: 15)
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("active directory domain") {
                // NW2: Use dropFirst().joined(separator:) to safely handle `key = value`
                // with spaces around `=`, and values that themselves contain `=`.
                let value = trimmed
                    .components(separatedBy: "=")
                    .dropFirst()
                    .joined(separator: "=")
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
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

    /// Returns true only for http/https URLs with a non-empty, non-blocked host,
    /// preventing file://, ftp://, and other schemes from reaching curl, and blocking
    /// SSRF to loopback addresses and cloud metadata services.
    /// NW4: Internal (not private) so unit tests can exercise the SSRF guard directly.
    func isAllowedURL(_ string: String) -> Bool {
        guard let u = URL(string: string),
              u.scheme == "http" || u.scheme == "https",
              let host = u.host, !host.isEmpty else { return false }
        // SSRF guard: loopback and cloud metadata endpoints must not be reachable.
        let blockedHosts = [
            "169.254.169.254", "metadata.google.internal", "fd00:ec2::254",
            "localhost", "127.0.0.1", "::1", "0.0.0.0"
        ]
        if blockedHosts.contains(host.lowercased()) { return false }
        if host.hasPrefix("169.254.") || host.hasPrefix("127.") { return false }
        return true
    }
}
