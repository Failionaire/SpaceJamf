/// The five diagnostic domains that SpaceJamf can collect and analyze.
enum DiagnosticArea: String, CaseIterable, Codable {
    case ad
    case jamf
    case certs
    case network
    case clock

    /// Human-readable label for use in terminal and HTML output.
    var displayName: String {
        switch self {
        case .ad:      return "Active Directory"
        case .jamf:    return "Jamf Pro"
        case .certs:   return "Certificates"
        case .network: return "Network / DNS"
        case .clock:   return "Clock / NTP"
        }
    }
}
