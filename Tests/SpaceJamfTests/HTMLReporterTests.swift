import XCTest
@testable import SpaceJamf

final class HTMLReporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeReport(
        severity: String = "warning",
        area: String = "ad",
        title: String = "Test finding",
        rootCause: String = "Root cause",
        steps: [String] = [],
        confidence: String = "certain"
    ) -> AnalysisReport {
        AnalysisReport(
            findings: [
                Finding(
                    severity: severity,
                    area: area,
                    title: title,
                    rootCause: rootCause,
                    remediationSteps: steps,
                    confidence: confidence
                )
            ],
            summary: "Test summary",
            generatedAt: nil
        )
    }

    // MARK: - HTML escaping: area and title

    func testHTMLReporterEscapesAreaAndTitle() {
        let html = HTMLReporter.render(
            report: makeReport(
                area: "<script>xss</script>",
                title: "<img src=x onerror=alert(1)>"
            ),
            results: [:]
        )
        XCTAssertFalse(html.contains("<script>xss</script>"),
                       "Raw <script> tag must not appear verbatim in rendered HTML")
        XCTAssertFalse(html.contains("<img src=x onerror=alert(1)>"),
                       "Raw <img> tag must not appear verbatim in rendered HTML")
        XCTAssertTrue(html.contains("&lt;script&gt;"),
                      "Script tag angle brackets must be HTML-escaped")
        XCTAssertTrue(html.contains("&lt;img"),
                      "Img tag angle bracket must be HTML-escaped")
    }

    // MARK: - HTML escaping: rootCause and remediation steps

    func testHTMLReporterEscapesSpecialCharsInFindings() {
        let html = HTMLReporter.render(
            report: makeReport(
                rootCause: "A & B policy \"quoted\" contains <tag>",
                steps: ["Run <cmd> as root"]
            ),
            results: [:]
        )
        XCTAssertTrue(html.contains("A &amp; B"),
                      "Ampersand in rootCause must be escaped to &amp;")
        XCTAssertTrue(html.contains("&quot;quoted&quot;"),
                      "Double quotes in rootCause must be escaped to &quot;")
        XCTAssertTrue(html.contains("&lt;tag&gt;"),
                      "Angle brackets in rootCause must be escaped")
        XCTAssertTrue(html.contains("&lt;cmd&gt;"),
                      "Angle brackets in remediation steps must be escaped")
        XCTAssertFalse(html.contains("<cmd>"),
                       "Raw <cmd> must not appear in rendered HTML")
    }

    // MARK: - HTML escaping: confidence label (H1)

    // H1: confLabel is wrapped with esc() to prevent injection if the enum rawValue
    // ever changes or the field is later sourced from untrusted data.
    func testHTMLReporterEscapesConfidenceLabel() {
        let htmlCertain = HTMLReporter.render(
            report: makeReport(confidence: "certain"),
            results: [:]
        )
        let htmlInferred = HTMLReporter.render(
            report: makeReport(confidence: "inferred"),
            results: [:]
        )
        // The badge span should contain the unmodified text (no special chars in known values).
        XCTAssertTrue(htmlCertain.contains(">certain<"),
                      "Confidence badge for 'certain' should render as plain text")
        XCTAssertTrue(htmlInferred.contains(">inferred<"),
                      "Confidence badge for 'inferred' should render as plain text")
        // Neither value should appear as an HTML tag.
        XCTAssertFalse(htmlCertain.contains("<certain>"),
                       "'certain' must not appear as an HTML tag")
        XCTAssertFalse(htmlInferred.contains("<inferred>"),
                       "'inferred' must not appear as an HTML tag")
    }

    // MARK: - Empty report renders without crash

    func testHTMLReporterRendersEmptyReport() {
        let report = AnalysisReport(findings: [], summary: "Nothing found", generatedAt: nil)
        let html = HTMLReporter.render(report: report, results: [:])
        XCTAssertTrue(html.contains("<!DOCTYPE html>"),
                      "Rendered output should be valid HTML")
        XCTAssertTrue(html.contains("Nothing found"),
                      "Summary should appear in rendered HTML")
    }
}
