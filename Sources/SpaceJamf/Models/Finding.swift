import Foundation

enum Severity: String, Codable, CaseIterable, Comparable {
    case critical
    case warning
    case info

    private var order: Int {
        switch self {
        case .critical: return 2
        case .warning:  return 1
        case .info:     return 0
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.order < rhs.order
    }
}

enum Confidence: String, Codable {
    /// The output clearly demonstrates the issue.
    case certain
    /// The issue is deduced from indirect evidence.
    case inferred
}

struct Finding: Codable {
    /// Raw severity string from Claude (e.g. "critical", "warning", "info").
    /// Stored as String so an unexpected value does not discard the entire analysis
    /// during JSON decoding (NEW-9). Use `resolvedSeverity` for rendering logic.
    let severity: String
    /// Matches a DiagnosticArea raw value (e.g. "ad", "jamf"). String to be
    /// resilient against unexpected values from Claude.
    let area: String
    let title: String
    let rootCause: String
    let remediationSteps: [String]
    /// Raw confidence string from Claude. Use `resolvedConfidence` for rendering.
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case severity
        case area
        case title
        case rootCause         = "root_cause"
        case remediationSteps  = "remediation_steps"
        case confidence
    }

    /// Coerces the raw severity string to a `Severity` value. Falls back to `.info`
    /// for any unexpected string so a single bad Claude output does not break rendering.
    var resolvedSeverity: Severity { Severity(rawValue: severity) ?? .info }

    /// Coerces the raw confidence string to a `Confidence` value. Falls back to
    /// `.inferred` for any unexpected string.
    var resolvedConfidence: Confidence { Confidence(rawValue: confidence) ?? .inferred }
}
