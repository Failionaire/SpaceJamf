import Foundation

// Per-collector diagnostic data.
// rawOutput is stored locally only and never sent over the network.
// scrubbedOutput is populated by DiagnoseCommand via Scrubber before any outbound use.
struct DiagnosticResult {
    let area: DiagnosticArea
    /// Raw command output — never leaves the device.
    let rawOutput: String
    /// Redacted copy safe to send to the Claude API. Nil until explicitly set by Scrubber.
    var scrubbedOutput: String?
    /// Exit codes keyed by command label (e.g. "dsconfigad", "klist").
    let exitCodes: [String: Int32]
    let timestamp: Date

    init(area: DiagnosticArea, rawOutput: String, exitCodes: [String: Int32]) {
        self.area = area
        self.rawOutput = rawOutput
        self.scrubbedOutput = nil
        self.exitCodes = exitCodes
        self.timestamp = Date()
    }
}
