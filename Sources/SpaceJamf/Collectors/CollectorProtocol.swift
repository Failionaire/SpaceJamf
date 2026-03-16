/// Every diagnostic collector conforms to this protocol.
///
/// `DiagnoseCommand` inspects `requiresElevation` on all collectors **before**
/// running any of them, printing upfront warnings for collectors that will
/// produce degraded results if not running as root.
protocol CollectorProtocol {
    var area: DiagnosticArea { get }
    /// Whether this collector needs root to return complete results.
    var requiresElevation: Bool { get }
    /// Run all commands for this collector and return the raw result.
    func collect() async -> DiagnosticResult
}
