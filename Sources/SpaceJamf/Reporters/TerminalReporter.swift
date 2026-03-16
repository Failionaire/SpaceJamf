import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum TerminalReporter {

    // MARK: - ANSI codes

    /// True when stdout is a real TTY and NO_COLOR is not set.
    /// When false all ANSI sequences are suppressed so piped/redirected
    /// output is free of escape characters (L-20).
    private static let ansiEnabled: Bool =
        isatty(STDOUT_FILENO) != 0 &&
        ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    private static let reset  = ansiEnabled ? "\u{1B}[0m" : ""
    private static let bold   = ansiEnabled ? "\u{1B}[1m" : ""
    private static let dim    = ansiEnabled ? "\u{1B}[2m" : ""
    private static let red    = ansiEnabled ? "\u{1B}[31m" : ""
    private static let yellow = ansiEnabled ? "\u{1B}[33m" : ""
    private static let blue   = ansiEnabled ? "\u{1B}[34m" : ""
    private static let green  = ansiEnabled ? "\u{1B}[32m" : ""
    private static let cyan   = ansiEnabled ? "\u{1B}[36m" : ""
    private static let purple = ansiEnabled ? "\u{1B}[35m" : ""

    // MARK: - Full AI report

    static func render(report: AnalysisReport, results: [DiagnosticArea: DiagnosticResult]) {
        printHeader("SpaceJamf Diagnostic Report")

        print("\(bold)Summary\(reset)")
        print("  \(report.summary)\n")

        let sorted = report.findings.sorted { $0.resolvedSeverity > $1.resolvedSeverity }

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
        let badge      = severityBadge(finding.resolvedSeverity)
        let confidence = finding.resolvedConfidence == .inferred
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
        let critical = findings.filter { $0.resolvedSeverity == .critical }.count
        let warnings = findings.filter { $0.resolvedSeverity == .warning  }.count
        let infos    = findings.filter { $0.resolvedSeverity == .info     }.count

        let critStr = critical > 0 ? "\(bold)\(red)\(critical) critical\(reset)"   : "\(dim)0 critical\(reset)"
        let warnStr = warnings > 0 ? "\(bold)\(yellow)\(warnings) warning\(reset)" : "\(dim)0 warning\(reset)"
        let infoStr = infos    > 0 ? "\(bold)\(blue)\(infos) info\(reset)"         : "\(dim)0 info\(reset)"

        print("\(dim)────────────────────────────────────────\(reset)")
        print("  \(critStr)   \(warnStr)   \(infoStr)")
        print("\(dim)────────────────────────────────────────\(reset)\n")
    }

    private static func printHeader(_ title: String) {
        // Use a fixed-width ASCII symbol instead of an emoji to avoid double-width
        // glyph alignment issues in terminals (L-13).
        let displayTitle = title.count <= 35
            ? title
            : String(title.prefix(32)) + "..."
        print()
        print("\(bold)\(cyan)╔══════════════════════════════════════════╗\(reset)")
        print("\(bold)\(cyan)║  [*]  \(displayTitle.padding(toLength: 35, withPad: " ", startingAt: 0))║\(reset)")
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
