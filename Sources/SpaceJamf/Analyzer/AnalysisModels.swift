import Foundation

/// The full report returned by Claude and passed to reporters.
struct AnalysisReport: Codable, Sendable {
    let findings: [Finding]
    let summary: String
    /// Set client-side immediately after decoding. Not present in Claude's JSON
    /// response but persisted when saving reports to disk.
    private(set) var generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case findings
        case summary
        case generatedAt = "generated_at"
    }

    /// Explicit init so the access level remains `internal` even though
    /// `generatedAt` has a `private` setter (a `private(set)` property can
    /// cause the synthesised memberwise init to become file-private in Swift).
    init(findings: [Finding], summary: String, generatedAt: Date? = nil) {
        self.findings    = findings
        self.summary     = summary
        self.generatedAt = generatedAt
    }

    /// Returns a copy with the generatedAt timestamp stamped.
    /// Using a copy function rather than a direct setter keeps the field
    /// private(set) while still allowing ClaudeClient to stamp it post-decode.
    func withGeneratedAt(_ date: Date) -> AnalysisReport {
        var copy = self
        copy.generatedAt = date
        return copy
    }
}

// MARK: - Shared codec

extension AnalysisReport {
    /// Shared encoder for persisting reports to disk. Uses ISO 8601 date formatting
    /// so saved JSON files are human-readable and greppable.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting     = .prettyPrinted
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Shared decoder for loading persisted reports from disk.
    /// Must use ISO 8601 to match `encoder`.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
