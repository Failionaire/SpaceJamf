import XCTest
@testable import SpaceJamf

final class ClaudeClientTests: XCTestCase {

    // MARK: - extractJSON

    func testExtractJSONStripsMarkdownFences() {
        let fenced = """
        ```json
        {"summary": "test", "findings": []}
        ```
        """
        let result = ClaudeClient.extractJSON(from: fenced)
        XCTAssertTrue(result.hasPrefix("{"), "Should start with '{' after stripping fences")
        XCTAssertTrue(result.hasSuffix("}"), "Should end with '}' after stripping fences")
        XCTAssertFalse(result.contains("```"), "Markdown fences should be removed")
    }

    func testExtractJSONHandlesNestedBraces() {
        let nested = #"{"summary": "outer", "findings": [{"title": "inner { brace }"}]}"#
        let result = ClaudeClient.extractJSON(from: nested)
        XCTAssertEqual(result, nested,
                       "Nested braces in field values should not prematurely end extraction")
    }

    // T1: no braces — should return the original text unchanged
    func testExtractJSONNoBraces() {
        let plain = "No JSON here at all."
        let result = ClaudeClient.extractJSON(from: plain)
        XCTAssertEqual(result, plain,
                       "Text with no braces should be returned unchanged")
    }

    // T2: triple-backtick fence without a language tag (``` rather than ```json)
    func testExtractJSONStripsPlainBacktickFence() {
        let fenced = """
        ```
        {"summary": "no lang tag", "findings": []}
        ```
        """
        let result = ClaudeClient.extractJSON(from: fenced)
        XCTAssertTrue(result.hasPrefix("{"), "Should start with '{' after stripping a plain ``` fence")
        XCTAssertTrue(result.hasSuffix("}"), "Should end with '}'")
        XCTAssertFalse(result.contains("```"), "Backtick fences must be removed regardless of language tag")
    }

    // T3: preamble text before the JSON object
    func testExtractJSONSkipsPreamble() {
        let withPreamble = "Here is the analysis:\n{\"summary\": \"ok\", \"findings\": []}"
        let result = ClaudeClient.extractJSON(from: withPreamble)
        XCTAssertTrue(result.hasPrefix("{"), "JSON extraction should skip leading preamble text")
        XCTAssertTrue(result.hasSuffix("}"), "Extracted JSON should end with '}'")
        XCTAssertFalse(result.contains("Here is"), "Preamble text should not appear in the extracted JSON")
    }

    // T9: documents the known limitation of the brace-depth counter.
    // A lone '}' inside a string value tricks the counter into stopping early,
    // producing a syntactically-incomplete fragment. Verifies no crash occurs.
    func testExtractJSONPrematureTerminationOnUnbalancedCloseBrace() {
        // The '}' embedded in "missing }" causes depth to reach 0 before the real
        // end of the object, so extraction terminates at that inner '}'.
        let input = #"{"summary": "missing }", "findings": []}"#
        let result = ClaudeClient.extractJSON(from: input)
        XCTAssertFalse(result.isEmpty,
                       "extractJSON must not return an empty string for unbalanced input")
        XCTAssertTrue(result.hasPrefix("{") && result.hasSuffix("}"),
                      "Returned fragment should still be brace-delimited")
        // The result is shorter than the full input — confirms premature termination.
        XCTAssertLessThan(result.count, input.count,
                          "Unbalanced '}' in a string value should cause premature extraction")
    }

    // MARK: - validateAPIKey (T8)

    func testValidateAPIKeyThrowsOnEmptyKey() throws {
        XCTAssertThrowsError(try ClaudeClient.validateAPIKey(""),
                             "Empty string should throw invalidConfiguration")
    }

    func testValidateAPIKeyThrowsOnWhitespaceOnlyKey() throws {
        XCTAssertThrowsError(try ClaudeClient.validateAPIKey("   "),
                             "Whitespace-only key should throw invalidConfiguration")
    }

    func testValidateAPIKeyPassesForNonEmptyKey() throws {
        XCTAssertNoThrow(try ClaudeClient.validateAPIKey("sk-ant-abc123"),
                         "A non-blank key should pass pre-flight validation")
    }

    // MARK: - AnalysisReport round-trip (T4)

    func testAnalysisReportRoundTrip() throws {
        let original = AnalysisReport(
            findings: [],
            summary: "Round-trip test",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data    = try AnalysisReport.encoder.encode(original)
        let decoded = try AnalysisReport.decoder.decode(AnalysisReport.self, from: data)

        // generatedAt is stored as ISO 8601; sub-second precision is lost, so compare
        // to the nearest second.
        let originalSeconds = original.generatedAt.map { Int($0.timeIntervalSince1970) }
        let decodedSeconds  = decoded.generatedAt.map  { Int($0.timeIntervalSince1970) }
        XCTAssertEqual(originalSeconds, decodedSeconds,
                       "generatedAt should survive a JSON encode/decode round-trip")
        XCTAssertEqual(decoded.summary, original.summary)
    }
}

// MARK: - Finding tests (T5)

final class FindingTests: XCTestCase {

    // T5: resolvedSeverity falls back to .info for an unrecognised string
    func testResolvedSeverityFallsBackToInfo() {
        let finding = Finding(
            severity: "not_a_real_severity",
            area: "ad",
            title: "Test",
            rootCause: "n/a",
            remediationSteps: [],
            confidence: "certain"
        )
        XCTAssertEqual(finding.resolvedSeverity, .info,
                       "Unrecognised severity string should fall back to .info")
    }

    func testResolvedConfidenceFallsBackToInferred() {
        let finding = Finding(
            severity: "warning",
            area: "ad",
            title: "Test",
            rootCause: "n/a",
            remediationSteps: [],
            confidence: "definitely_maybe"
        )
        XCTAssertEqual(finding.resolvedConfidence, .inferred,
                       "Unrecognised confidence string should fall back to .inferred")
    }
}

