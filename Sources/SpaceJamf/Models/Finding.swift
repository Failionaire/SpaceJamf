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

enum Confidence: String, Codable, CaseIterable {
    /// The output clearly demonstrates the issue.
    case certain
    /// The issue is deduced from indirect evidence.
    case inferred
}

/// A single diagnostic finding decoded from Claude's JSON response.
struct Finding: Codable, Sendable {
    /// Raw severity string from Claude (e.g. "critical", "warning", "info").
    /// Stored as String so an unexpected value does not discard the entire analysis
    /// during JSON decoding. Use `resolvedSeverity` for rendering logic.
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
    /// Note: writes to stderr as a side effect when the value is unrecognised.
    /// If SpaceJamf is ever extracted as a library this should be refactored to return
    /// a `Result` or log via a proper logging facade instead.
    var resolvedSeverity: Severity {
        if let s = Severity(rawValue: severity) { return s }
        err("Warning: unrecognised severity '\(severity)' in finding '\(title)' \u2014 treating as info")
        return .info
    }

    /// Coerces the raw confidence string to a `Confidence` value. Falls back to
    /// `.inferred` for any unexpected string.
    /// Note: writes to stderr as a side effect when the value is unrecognised.
    /// See `resolvedSeverity` for the rationale and future refactor guidance.
    var resolvedConfidence: Confidence {
        if let c = Confidence(rawValue: confidence) { return c }
        err("Warning: unrecognised confidence '\(confidence)' in finding '\(title)' \u2014 treating as inferred")
        return .inferred
    }
}

// MARK: - Severity count helper

extension Sequence where Element == Finding {
    /// Returns severity counts in a single pass — avoids three separate `.filter` calls
    /// in HTMLReporter and TerminalReporter (H2/TR2).
    func severityCounts() -> (critical: Int, warning: Int, info: Int) {
        var critical = 0, warning = 0, info = 0
        for finding in self {
            switch finding.resolvedSeverity {
            case .critical: critical += 1
            case .warning:  warning  += 1
            case .info:     info     += 1
            }
        }
        return (critical, warning, info)
    }
}
