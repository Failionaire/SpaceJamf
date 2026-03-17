import XCTest
@testable import SpaceJamf

final class PromptBuilderTests: XCTestCase {

    func testPromptBuilderTruncatesLargeSections() async {
        // Create a DiagnosticResult with scrubbedOutput exceeding the 8 KB cap.
        let largeOutput = String(repeating: "A", count: 10_000)
        let result = DiagnosticResult(area: .ad, rawOutput: "raw", exitCodes: [:])
            .withScrubbedOutput(largeOutput)

        let prompt = await PromptBuilder.build(from: [result])
        XCTAssertNotNil(prompt, "build(from:) should return a prompt when results are non-empty")
        XCTAssertTrue(prompt!.user.contains("[output truncated at 8 KB]"),
                      "Sections larger than 8 KB should include a truncation notice")
        XCTAssertFalse(prompt!.user.contains(largeOutput),
                       "Full oversized output must not appear in the prompt")
    }

    // T6: multiple areas appear in alphabetical order and are separated correctly
    func testPromptBuilderOrdersAreasAlphabetically() async {
        // Insert results in reverse alphabetical order to confirm sorting is applied.
        let networkResult = DiagnosticResult(area: .network, rawOutput: "net", exitCodes: [:])
            .withScrubbedOutput("net output")
        let adResult = DiagnosticResult(area: .ad, rawOutput: "ad", exitCodes: [:])
            .withScrubbedOutput("ad output")
        let clockResult = DiagnosticResult(area: .clock, rawOutput: "clock", exitCodes: [:])
            .withScrubbedOutput("clock output")

        let prompt = await PromptBuilder.build(from: [networkResult, adResult, clockResult])
        XCTAssertNotNil(prompt)
        let user = prompt!.user

        // All three sections must appear, and ad must come before clock which comes before network.
        let adIdx      = user.range(of: "Active Directory")?.lowerBound
        let clockIdx   = user.range(of: "Clock")?.lowerBound
        let networkIdx = user.range(of: "Network")?.lowerBound

        XCTAssertNotNil(adIdx,      "AD section should appear in the prompt")
        XCTAssertNotNil(clockIdx,   "Clock section should appear in the prompt")
        XCTAssertNotNil(networkIdx, "Network section should appear in the prompt")

        if let a = adIdx, let c = clockIdx, let n = networkIdx {
            XCTAssertLessThan(a, c, "AD section should appear before Clock")
            XCTAssertLessThan(c, n, "Clock section should appear before Network")
        }

        XCTAssertTrue(user.contains("---"), "Sections should be separated by a divider")
    }

    // T7: empty results array returns nil (P3 guard)
    func testPromptBuilderReturnsNilForEmptyResults() async {
        let prompt = await PromptBuilder.build(from: [])
        XCTAssertNil(prompt, "build(from: []) should return nil to avoid a wasted API call")
    }
}

