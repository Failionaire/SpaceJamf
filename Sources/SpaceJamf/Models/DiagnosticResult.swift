import Foundation

// Per-collector diagnostic data.
// rawOutput is stored locally only and never sent over the network.
// scrubbedOutput is set via withScrubbedOutput(_:) by DiagnoseCommand after Scrubber runs.
struct DiagnosticResult: Sendable {
    let area: DiagnosticArea
    /// Raw command output — never leaves the device.
    let rawOutput: String
    /// Redacted copy safe to send to the Claude API.
    /// Nil until explicitly set via withScrubbedOutput(_:).
    private(set) var scrubbedOutput: String?
    /// Exit codes keyed by command label (e.g. "dsconfigad", "klist").
    let exitCodes: [String: Int32]
    /// The time at which this collector began running.
    let collectedAt: Date

    init(area: DiagnosticArea, rawOutput: String, exitCodes: [String: Int32]) {
        self.area = area
        self.rawOutput = rawOutput
        self.scrubbedOutput = nil
        self.exitCodes = exitCodes
        self.collectedAt = Date()
    }

    /// Returns a copy of this result with the scrubbed output set.
    /// The private(set) accessor prevents accidental writes from outside this file;
    /// this function is the single sanctioned mutation point.
    func withScrubbedOutput(_ output: String) -> DiagnosticResult {
        var copy = self
        copy.scrubbedOutput = output
        return copy
    }
}
