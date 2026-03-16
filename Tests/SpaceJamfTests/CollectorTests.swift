import XCTest
@testable import SpaceJamf

final class CollectorTests: XCTestCase {

    // MARK: - Fixture helpers

    private func fixture(_ name: String) -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("Fixture not found: \(name).txt")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Fixtures: structural sanity

    func testADBoundFixtureHasExpectedFields() {
        let text = fixture("ad_bound")
        XCTAssertTrue(text.contains("Active Directory Domain"),
                      "ad_bound.txt should contain 'Active Directory Domain'")
        XCTAssertTrue(text.contains("Computer Account"),
                      "ad_bound.txt should contain 'Computer Account'")
    }

    func testADUnboundFixtureIndicatesNotBound() {
        let text = fixture("ad_unbound")
        XCTAssertFalse(text.isEmpty, "ad_unbound.txt must not be empty")
    }

    func testJamfConnectedFixtureContainsJSSReference() {
        let text = fixture("jamf_connected")
        XCTAssertTrue(
            text.contains("JSS") || text.contains("jss") || text.contains("Jamf"),
            "jamf_connected.txt should reference the JSS"
        )
    }

    func testKlistExpiredFixtureContainsExpiredMarker() {
        let text = fixture("klist_expired")
        XCTAssertTrue(text.contains("EXPIRED") || text.contains("expired"),
                      "klist_expired.txt should indicate an expired ticket")
    }

    // MARK: - Fixtures: scrubber removes IPs

    func testKlistExpiredFixtureIPsAreRedacted() {
        let text     = fixture("klist_expired")
        let scrubbed = Scrubber.scrub(text)
        // The fixture intentionally embeds "10.20.30.40" to verify the scrubber removes it
        XCTAssertNil(
            scrubbed.range(of: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, options: .regularExpression),
            "klist_expired.txt must not contain a raw IPv4 address after scrubbing"
        )
    }

    // MARK: - DiagnosticArea

    func testDiagnosticAreaRawValues() {
        XCTAssertEqual(DiagnosticArea.ad.rawValue,      "ad")
        XCTAssertEqual(DiagnosticArea.jamf.rawValue,    "jamf")
        XCTAssertEqual(DiagnosticArea.certs.rawValue,   "certs")
        XCTAssertEqual(DiagnosticArea.network.rawValue, "network")
        XCTAssertEqual(DiagnosticArea.clock.rawValue,   "clock")
    }

    func testDiagnosticAreaAllCasesCount() {
        XCTAssertEqual(DiagnosticArea.allCases.count, 5)
    }

    // MARK: - CollectorProtocol: requiresElevation

    func testADCollectorRequiresElevation() {
        XCTAssertTrue(ADCollector().requiresElevation)
    }

    func testJamfCollectorDoesNotRequireElevation() {
        XCTAssertFalse(JamfCollector().requiresElevation)
    }

    func testCertCollectorDoesNotRequireElevation() {
        XCTAssertFalse(CertCollector().requiresElevation)
    }

    func testNetworkCollectorDoesNotRequireElevation() {
        XCTAssertFalse(NetworkCollector().requiresElevation)
    }

    func testClockCollectorDoesNotRequireElevation() {
        XCTAssertFalse(ClockCollector().requiresElevation)
    }

    // MARK: - CollectorProtocol: area assignment

    func testCollectorAreasMatchExpected() {
        XCTAssertEqual(ADCollector().area,      .ad)
        XCTAssertEqual(JamfCollector().area,    .jamf)
        XCTAssertEqual(CertCollector().area,    .certs)
        XCTAssertEqual(NetworkCollector().area, .network)
        XCTAssertEqual(ClockCollector().area,   .clock)
    }

    // MARK: - JamfCollector: graceful handling when binary absent

    func testJamfCollectorHandlesMissingBinary() async {
        var collector = JamfCollector()
        collector.jamfPath = "/nonexistent/path/to/jamf"
        let result = await collector.collect()
        XCTAssertEqual(result.area, .jamf)
        XCTAssertTrue(
            result.rawOutput.contains("Jamf binary not found"),
            "Should report missing binary, got: \(result.rawOutput)"
        )
        XCTAssertEqual(result.exitCodes["jamf"], -1)
    }

    // MARK: - Severity ordering

    func testSeverityOrdering() {
        XCTAssertTrue(Severity.info < Severity.warning)
        XCTAssertTrue(Severity.warning < Severity.critical)
        XCTAssertFalse(Severity.critical < Severity.info)
    }

    func testSeveritySortDescending() {
        let input: [Severity] = [.info, .critical, .warning, .info, .critical]
        let sorted = input.sorted { $0 > $1 }
        XCTAssertEqual(sorted, [.critical, .critical, .warning, .info, .info])
    }
}
