import Foundation

enum HTMLReporter {

    // MARK: - Public API

    /// Render a self-contained single-file HTML report.
    static func render(
        report: AnalysisReport,
        results: [DiagnosticArea: DiagnosticResult]
    ) -> String {
        let timestamp = DateFormatter.localizedString(
            from: report.generatedAt ?? Date(),
            dateStyle: .long,
            timeStyle: .long
        )

        let sorted = report.findings.sorted { $0.severity > $1.severity }
        let findingsHTML = sorted.enumerated()
            .map { renderFinding($0.element, index: $0.offset + 1) }
            .joined(separator: "\n")

        let rawSections: String
        if results.isEmpty {
            rawSections = "<p class=\"muted\">Raw output not available (re-render from saved JSON).</p>"
        } else {
            rawSections = results
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { renderRawSection(area: $0.key, result: $0.value) }
                .joined(separator: "\n")
        }

        let critical = sorted.filter { $0.severity == .critical }.count
        let warnings = sorted.filter { $0.severity == .warning  }.count
        let infos    = sorted.filter { $0.severity == .info     }.count

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>SpaceJamf Report — \(timestamp)</title>
            <style>\(css)</style>
        </head>
        <body>
            <header>
                <div class="header-inner">
                    <h1>🛸 SpaceJamf Diagnostic Report</h1>
                    <p class="timestamp">\(esc(timestamp))</p>
                </div>
            </header>
            <main>
                <section class="summary-section">
                    <h2>Summary</h2>
                    <p>\(esc(report.summary))</p>
                    <div class="counts">
                        <span class="count count-critical">\(critical) critical</span>
                        <span class="count count-warning">\(warnings) warning</span>
                        <span class="count count-info">\(infos) info</span>
                    </div>
                </section>

                <section>
                    <h2>Findings</h2>
                    \(sorted.isEmpty ? "<p class=\"muted\">No issues found.</p>" : findingsHTML)
                </section>

                <section>
                    <h2>Raw Diagnostic Output</h2>
                    <p class="muted">
                        Sensitive data has been redacted before collection. This output
                        matches exactly what was sent to Claude.
                    </p>
                    \(rawSections)
                </section>
            </main>
            <script>\(javascript)</script>
        </body>
        </html>
        """
    }

    // MARK: - Fragment renderers

    private static func renderFinding(_ finding: Finding, index: Int) -> String {
        let severityClass = "finding-\(finding.severity.rawValue)"
        let badgeClass    = "badge-\(finding.severity.rawValue)"
        let confClass     = finding.confidence == .inferred ? "badge-inferred" : "badge-certain"
        let confLabel     = finding.confidence.rawValue

        let stepsHTML = finding.remediationSteps.isEmpty
            ? ""
            : "<ol>" + finding.remediationSteps.map { "<li>\(esc($0))</li>" }.joined() + "</ol>"

        return """
        <div class="finding \(severityClass)">
            <div class="finding-header" role="button" tabindex="0"
                 aria-expanded="true" aria-controls="finding-\(index)"
                 onclick="toggleFinding(this)"
                 onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();toggleFinding(this);}">
                <span class="badge \(badgeClass)">\(finding.severity.rawValue.uppercased())</span>
                <span class="area-label">\(esc(finding.area.uppercased()))</span>
                <span class="badge \(confClass)">\(confLabel)</span>
                <span class="finding-title">\(index). \(esc(finding.title))</span>
            </div>
            <div class="finding-body" id="finding-\(index)">
                <p><strong>Root Cause:</strong> \(esc(finding.rootCause))</p>
                \(stepsHTML.isEmpty ? "" : "<div class=\"remediation\"><strong>Remediation Steps:</strong>\(stepsHTML)</div>")
            </div>
        </div>
        """
    }

    private static func renderRawSection(area: DiagnosticArea, result: DiagnosticResult) -> String {
        let exitSummary = result.exitCodes
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "  |  ")

        return """
        <details class="raw-area">
            <summary><strong>\(area.rawValue.uppercased())</strong>
                \(exitSummary.isEmpty ? "" : "<span class=\"exit-codes\">Exit codes: \(esc(exitSummary))</span>")
            </summary>
            <pre>\(esc(result.scrubbedOutput ?? ""))</pre>
        </details>
        """
    }

    // MARK: - HTML escaping

    private static func esc(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - CSS

    private static let css = """
    :root{--critical:#dc2626;--warning:#d97706;--info:#3b82f6;--certain:#10b981;
    --inferred:#8b5cf6;--bg:#0f172a;--surface:#1e293b;--border:#334155;
    --text:#e2e8f0;--muted:#64748b;--radius:0.5rem;}
    *{box-sizing:border-box;margin:0;padding:0;}
    body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',Segoe UI,sans-serif;
    background:var(--bg);color:var(--text);line-height:1.6;}
    a{color:#60a5fa;}
    header{background:var(--surface);border-bottom:1px solid var(--border);padding:1.5rem 2rem;}
    .header-inner h1{font-size:1.5rem;font-weight:700;}
    .timestamp{color:var(--muted);font-size:0.85rem;margin-top:.25rem;}
    main{max-width:960px;margin:2rem auto;padding:0 1.5rem;}
    section{margin-bottom:2.5rem;}
    h2{font-size:1rem;font-weight:700;text-transform:uppercase;letter-spacing:.08em;
    color:var(--muted);margin-bottom:1rem;}
    .summary-section p{background:var(--surface);padding:1.25rem;border-radius:var(--radius);
    border:1px solid var(--border);font-size:1.05rem;}
    .counts{display:flex;gap:.75rem;margin-top:.75rem;}
    .count{padding:.25rem .75rem;border-radius:var(--radius);font-size:.8rem;font-weight:700;}
    .count-critical{background:#450a0a;color:#fca5a5;}
    .count-warning{background:#431407;color:#fcd34d;}
    .count-info{background:#0c1a3d;color:#93c5fd;}
    .finding{border:1px solid var(--border);border-radius:var(--radius);
    margin-bottom:.75rem;overflow:hidden;}
    .finding-critical{border-left:4px solid var(--critical);}
    .finding-warning{border-left:4px solid var(--warning);}
    .finding-info{border-left:4px solid var(--info);}
    .finding-header{display:flex;align-items:center;flex-wrap:wrap;gap:.5rem;
    padding:.875rem 1.25rem;background:var(--surface);cursor:pointer;user-select:none;}
    .finding-header:hover{background:#263044;}
    .finding-title{font-weight:600;font-size:.95rem;}
    .finding-body{padding:1rem 1.25rem;border-top:1px solid var(--border);}
    .finding-body p{margin-bottom:.5rem;}
    .badge{padding:.2rem .5rem;border-radius:.25rem;font-size:.72rem;
    font-weight:700;letter-spacing:.04em;text-transform:uppercase;}
    .badge-critical{background:var(--critical);color:#fff;}
    .badge-warning{background:var(--warning);color:#fff;}
    .badge-info{background:var(--info);color:#fff;}
    .badge-certain{background:#064e3b;color:#34d399;}
    .badge-inferred{background:#2e1065;color:#a78bfa;}
    .area-label{font-size:.72rem;font-weight:700;letter-spacing:.06em;color:var(--muted);}
    .remediation{margin-top:.5rem;}
    .remediation ol{margin:.5rem 0 0 1.5rem;}
    .remediation li{margin-bottom:.3rem;}
    details.raw-area{border:1px solid var(--border);border-radius:var(--radius);
    margin-bottom:.625rem;}
    details.raw-area>summary{padding:.7rem 1rem;cursor:pointer;background:var(--surface);
    font-size:.875rem;border-radius:var(--radius);list-style:none;display:flex;
    align-items:center;gap:.75rem;}
    details.raw-area[open]>summary{border-radius:var(--radius) var(--radius) 0 0;
    border-bottom:1px solid var(--border);}
    details.raw-area>pre{padding:1rem;font-size:.78rem;line-height:1.55;overflow-x:auto;
    white-space:pre-wrap;word-break:break-all;
    font-family:'SF Mono',Menlo,Consolas,monospace;color:var(--muted);}
    .exit-codes{font-size:.75rem;color:var(--muted);font-weight:400;}
    .muted{color:var(--muted);font-size:.9rem;}
    """

    // MARK: - JavaScript

    private static let javascript = """
    function toggleFinding(header){
        var body=header.nextElementSibling;
        if(!body)return;
        var hidden=body.style.display==='none';
        body.style.display=hidden?'':'none';
        header.setAttribute('aria-expanded',String(hidden));
    }
    """
}
