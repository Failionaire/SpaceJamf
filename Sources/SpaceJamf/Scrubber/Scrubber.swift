import Foundation

/// Removes sensitive data from diagnostic output before it leaves the device.
///
/// Four categories are redacted:
///   - IPv4 and IPv6 address literals → `[IP_REDACTED]`
///   - MAC addresses                  → `[MAC REDACTED]`
///   - Kerberos base64 ticket blobs   → `[TICKET_REDACTED]`
///   - Lines containing passwords     → `[CREDENTIAL_REDACTED]`
enum Scrubber {

    // MARK: - Patterns

    /// Matches dotted-quad IPv4 addresses.
    private static let ipv4 = #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#

    /// Matches common IPv6 forms: full 8-group (e.g. 2001:0db8::…:7334) or compressed
    /// forms that contain `::` (e.g. fe80::1, ::1). Requiring `::` for compressed forms
    /// prevents false positives on MAC addresses and colon-delimited certificate serials.
    private static let ipv6 = #"(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|[0-9a-fA-F]{0,4}(?::[0-9a-fA-F]{0,4})*::(?:[0-9a-fA-F]{0,4}:)*[0-9a-fA-F]{0,4}"#

    /// Matches long base64 blobs that follow ticket/credential keywords in klist output.
    private static let kerberosBlob = #"(?<=Ticket|ticket|credential|Credential|Key|key)[\s=:]+[A-Za-z0-9+/]{40,}={0,2}"#

    /// SC1: Matches lines where "password" (whole-word, case-insensitive) precedes an
    /// `=` or `:` separator followed by a non-empty value. Using `\b` and requiring `[=:]`
    /// avoids over-redacting policy description lines such as "Password Policy:".
    private static let passwordLine = #"(?mi)^[^\n]*\bpassword\b[^\n]*[=:]\s*\S.*$"#

    /// SC2: Matches IEEE 802 MAC addresses in both colon and hyphen notation (case-insensitive).
    private static let macAddress = #"(?i)\b([0-9a-f]{2}[:\-]){5}[0-9a-f]{2}\b"#

    // SC3: Using NSRegularExpression for back-deployment to macOS 12/13.
    // When the minimum deployment target is raised to macOS 13+, these can
    // migrate to Swift Regex literals (#/…/#) for compile-time safety.
    //
    // Pre-compiled regex objects — compiled once at first use, never again.
    // Safety: each pattern is a compile-time literal and has been validated by
    // the test suite. A panic here is always a programmer error, not a runtime one.
    private static let ipv4Regex         = try! NSRegularExpression(pattern: ipv4)
    private static let ipv6Regex         = try! NSRegularExpression(pattern: ipv6)
    private static let kerberosBlobRegex = try! NSRegularExpression(pattern: kerberosBlob)
    private static let passwordLineRegex = try! NSRegularExpression(pattern: passwordLine)
    private static let macAddressRegex   = try! NSRegularExpression(pattern: macAddress)

    // MARK: - Public API

    static func scrub(_ input: String) -> String {
        var result = input
        // Order matters: credentials first (whole-line), then tickets (inline blobs),
        // then IPs (both families). Running credential scrubbing last could miss passwords
        // that already had their IP addresses replaced in a previous pass.
        // MAC addresses are scrubbed after IPs to avoid conflicts with the IPv6 pattern.
        result = apply(passwordLineRegex,   replacement: "[CREDENTIAL_REDACTED]", to: result)
        result = apply(kerberosBlobRegex,   replacement: " [TICKET_REDACTED]",   to: result)
        result = apply(ipv4Regex,           replacement: "[IP_REDACTED]",         to: result)
        result = apply(ipv6Regex,           replacement: "[IP_REDACTED]",         to: result)
        result = apply(macAddressRegex,     replacement: "[MAC REDACTED]",        to: result)
        return result
    }

    // MARK: - Helpers

    private static func apply(_ regex: NSRegularExpression, replacement: String, to input: String) -> String {
        // SC4: NSRange must cover the current (mutated) string, not the original;
        // recomputation on each call is intentional, not a missed optimisation.
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }
}
