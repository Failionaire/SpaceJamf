// Diagnostic areas that can be collected and analyzed.
enum DiagnosticArea: String, CaseIterable, Codable {
    case ad
    case jamf
    case certs
    case network
    case clock
}
