// Diagnostic areas that can be collected and analyzed.
enum DiagnosticArea: String, CaseIterable, Codable {
    case ad
    case jamf
    case certs
    case network
    case clock

    var displayName: String {
        switch self {
        case .ad:      return "Active Directory"
        case .jamf:    return "Jamf Pro"
        case .certs:   return "Certificates"
        case .network: return "Network"
        case .clock:   return "Clock / NTP"
        }
    }
}
