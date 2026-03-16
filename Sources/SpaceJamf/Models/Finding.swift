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
    let severity: Severity
    /// Matches a DiagnosticArea raw value (e.g. "ad", "jamf"). String to be
    /// resilient against unexpected values from Claude.
    let area: String
    let title: String
    let rootCause: String
    let remediationSteps: [String]
    let confidence: Confidence

    enum CodingKeys: String, CodingKey {
        case severity
        case area
        case title
        case rootCause         = "root_cause"
        case remediationSteps  = "remediation_steps"
        case confidence
    }
}
