import Foundation

enum TerminalReporter {

    // MARK: - ANSI codes

    private static let reset  = "\u{1B}[0m"
    private static let bold   = "\u{1B}[1m"
    private static let dim    = "\u{1B}[2m"
    private static let red    = "\u{1B}[31m"
    private static let yellow = "\u{1B}[33m"
    private static let blue   = "\u{1B}[34m"
    private static let green  = "\u{1B}[32m"
    private static let cyan   = "\u{1B}[36m"
    private static let purple = "\u{1B}[35m"

    // MARK: - Full AI report

    static func render(report: AnalysisReport, results: [DiagnosticArea: DiagnosticResult]) {
        printHeader("SpaceJamf Diagnostic Report")

        print("\(bold)Summary\(reset)")
        print("  \(report.summary)\n")

        let sorted = report.findings.sorted { $0.severity > $1.severity }

        if sorted.isEmpty {
            print("\(green)✓ No issues found.\(reset)")
        } else {
            print("\(bold)Findings  (\(sorted.count) total)\(reset)\n")
            for (i, finding) in sorted.enumerated() {
                renderFinding(finding, index: i + 1)
            }
            printSummaryBox(findings: sorted)
        }

        if !results.isEmpty {
            print("\n\(dim)Raw scrubbed output available — rerun with --output html for full details.\(reset)")
        }
    }

    // MARK: - No-Claude raw mode

    static func renderRaw(results: [DiagnosticArea: DiagnosticResult]) {
        printHeader("SpaceJamf Diagnostics  (--no-claude)")
        print("\(dim)Showing scrubbed diagnostic output. No AI analysis performed.\(reset)\n")

        for result in results.values.sorted(by: { $0.area.rawValue < $1.area.rawValue }) {
            print("\(bold)\(cyan)═══ \(result.area.rawValue.uppercased()) ═══\(reset)")
            let exitSummary = result.exitCodes
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "  ")
            if !exitSummary.isEmpty {
                print("\(dim)Exit codes: \(exitSummary)\(reset)")
            }
            print(result.scrubbedOutput ?? "")
        }
    }

    // MARK: - Helpers

    private static func renderFinding(_ finding: Finding, index: Int) {
        let badge      = severityBadge(finding.severity)
        let confidence = finding.confidence == .inferred
            ? "  \(dim)\(purple)[inferred]\(reset)"
            : "  \(dim)\(green)[certain]\(reset)"

        print("\(badge)  \(bold)\(index). \(finding.title)\(reset)\(confidence)")
        print("   \(dim)area:\(reset) \(finding.area.uppercased())")
        print("   \(dim)root cause:\(reset) \(finding.rootCause)")

        if !finding.remediationSteps.isEmpty {
            print("   \(dim)remediation:\(reset)")
            for (n, step) in finding.remediationSteps.enumerated() {
                print("     \(dim)\(n + 1).\(reset) \(step)")
            }
        }
        print()
    }

    private static func printSummaryBox(findings: [Finding]) {
        let critical = findings.filter { $0.severity == .critical }.count
        let warnings = findings.filter { $0.severity == .warning  }.count
        let infos    = findings.filter { $0.severity == .info     }.count

        let critStr = critical > 0 ? "\(bold)\(red)\(critical) critical\(reset)"   : "\(dim)0 critical\(reset)"
        let warnStr = warnings > 0 ? "\(bold)\(yellow)\(warnings) warning\(reset)" : "\(dim)0 warning\(reset)"
        let infoStr = infos    > 0 ? "\(bold)\(blue)\(infos) info\(reset)"         : "\(dim)0 info\(reset)"

        print("\(dim)────────────────────────────────────────\(reset)")
        print("  \(critStr)   \(warnStr)   \(infoStr)")
        print("\(dim)────────────────────────────────────────\(reset)\n")
    }

    private static func printHeader(_ title: String) {
        // Clamp to 34 chars + "..." to avoid overflowing the fixed-width box border
        let displayTitle = title.count <= 37
            ? title
            : String(title.prefix(34)) + "..."
        print()
        print("\(bold)\(cyan)╔══════════════════════════════════════════╗\(reset)")
        print("\(bold)\(cyan)║  🛸  \(displayTitle.padding(toLength: 37, withPad: " ", startingAt: 0))║\(reset)")
        print("\(bold)\(cyan)╚══════════════════════════════════════════╝\(reset)")
        print()
    }

    private static func severityBadge(_ severity: Severity) -> String {
        switch severity {
        case .critical: return "\(bold)\(red)[CRITICAL]\(reset)"
        case .warning:  return "\(bold)\(yellow)[WARNING] \(reset)"
        case .info:     return "\(bold)\(blue)[INFO]    \(reset)"
        }
    }
}
