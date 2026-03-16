import Foundation

/// The full report returned by Claude and passed to reporters.
struct AnalysisReport: Codable {
    let findings: [Finding]
    let summary: String
    /// Set client-side immediately after decoding. Not present in Claude's JSON
    /// response but persisted when saving reports to disk.
    var generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case findings
        case summary
        case generatedAt = "generated_at"
    }
}
