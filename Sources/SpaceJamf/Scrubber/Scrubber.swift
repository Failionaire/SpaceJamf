import Foundation

/// Removes sensitive data from diagnostic output before it leaves the device.
///
/// Three categories are redacted:
///   - IPv4 and IPv6 address literals → `[IP_REDACTED]`
///   - Kerberos base64 ticket blobs    → `[TICKET_REDACTED]`
///   - Lines containing passwords      → `[CREDENTIAL_REDACTED]`
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

    /// Matches any line that contains a password key-value pair.
    private static let passwordLine = #"(?m)^[^\n]*[Pp]assword[^\n]*:.*$"#

    // Pre-compiled regex objects — compiled once at first use, never again.
    private static let ipv4Regex         = try! NSRegularExpression(pattern: ipv4)
    private static let ipv6Regex         = try! NSRegularExpression(pattern: ipv6)
    private static let kerberosBlobRegex = try! NSRegularExpression(pattern: kerberosBlob)
    private static let passwordLineRegex = try! NSRegularExpression(pattern: passwordLine)

    // MARK: - Public API

    static func scrub(_ input: String) -> String {
        var result = input
        result = apply(passwordLineRegex,   replacement: "[CREDENTIAL_REDACTED]", to: result)
        result = apply(kerberosBlobRegex,   replacement: " [TICKET_REDACTED]",   to: result)
        result = apply(ipv4Regex,           replacement: "[IP_REDACTED]",         to: result)
        result = apply(ipv6Regex,           replacement: "[IP_REDACTED]",         to: result)
        return result
    }

    // MARK: - Helpers

    private static func apply(_ regex: NSRegularExpression, replacement: String, to input: String) -> String {
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }
}
