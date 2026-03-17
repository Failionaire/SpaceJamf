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
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("Failed to read fixture \(name).txt: \(error)")
            return ""
        }
    }

    // MARK: - Fixtures: structural sanity

    func testADBoundFixtureHasExpectedFields() {
        let text = fixture("ad_bound")
        XCTAssertTrue(text.contains("Active Directory Domain"),
                      "ad_bound.txt should contain 'Active Directory Domain'")
        XCTAssertTrue(text.contains("Computer Account"),
                      "ad_bound.txt should contain 'Computer Account'")
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
        // JA-1: JamfCollector now takes jamfPath via its designated initialiser.
        let collector = JamfCollector(jamfPath: "/nonexistent/path/to/jamf")
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

    // MARK: - DiagnosticResult defaults (L-15)

    func testDiagnosticResultDefaultScrubbedOutputIsNil() {
        let result = DiagnosticResult(area: .network, rawOutput: "test", exitCodes: [:])
        XCTAssertNil(result.scrubbedOutput,
                     "scrubbedOutput must be nil on a freshly initialised DiagnosticResult")
    }

    // MARK: - Fixture: ad_unbound (L-16)

    func testADUnboundFixtureIndicatesNotBound() {
        let text = fixture("ad_unbound")
        XCTAssertFalse(text.isEmpty, "ad_unbound.txt must not be empty")
        // Verify the fixture actually contains an unbound/not-connected marker
        let lowercased = text.lowercased()
        XCTAssertTrue(
            lowercased.contains("not bound") ||
            lowercased.contains("not joined") ||
            lowercased.contains("no domain") ||
            lowercased.contains("unable"),
            "ad_unbound.txt should contain a recognisable 'not bound' indicator, got: \(text.prefix(200))"
        )
    }

    // MARK: - DiagnoseCommand.parseAreas (H-3)

    func testParseAreasAllValid() {
        var cmd = DiagnoseCommand()
        cmd.areas = "ad,jamf,certs,network,clock"
        let areas = cmd.parseAreas()
        XCTAssertEqual(Set(areas), Set(DiagnosticArea.allCases))
        XCTAssertEqual(areas.count, 5)
    }

    func testParseAreasUnknownTokenSkipped() {
        var cmd = DiagnoseCommand()
        cmd.areas = "ad,bogusarea,clock"
        let areas = cmd.parseAreas()
        XCTAssertEqual(areas, [.ad, .clock],
                       "Unknown token should be silently skipped (after warning)")
    }

    func testParseAreasAllUnknownProducesEmpty() {
        var cmd = DiagnoseCommand()
        cmd.areas = "foo,bar,baz"
        let areas = cmd.parseAreas()
        XCTAssertTrue(areas.isEmpty, "All-unknown input should produce an empty array")
    }

    func testParseAreasDeduplicated() {
        var cmd = DiagnoseCommand()
        cmd.areas = "ad,clock,ad,clock"
        let areas = cmd.parseAreas()
        XCTAssertEqual(areas, [.ad, .clock], "Duplicate tokens should be removed")
    }

    // MARK: - NetworkCollector injectable URL/domain (NEW-13)

    // CT7: This test exercises the live collect() path against non-existent hosts.
    // It will make real DNS queries that fail; the test validates graceful failure,
    // not successful collection. Expected run time: <5 s with DNS timeout.
    func testNetworkCollectorInjectableProperties() async {
        var collector = NetworkCollector()
        collector.jssURL   = "https://test.example.com"
        collector.adDomain = "corp.example.com"
        // Collecting against injected non-existent hosts will fail at the network
        // layer, but the result should still contain the injected values in output.
        let result = await collector.collect()
        XCTAssertEqual(result.area, .network)
        XCTAssertTrue(
            result.rawOutput.contains("test.example.com") ||
            result.rawOutput.contains("corp.example.com"),
            "rawOutput should reference the injected URL or domain"
        )
    }

    // MARK: - NetworkCollector.isAllowedURL (CT1)

    func testIsAllowedURL_validHTTPS() {
        XCTAssertTrue(NetworkCollector().isAllowedURL("https://jamf.example.com"),
                      "https URL should be allowed")
    }

    func testIsAllowedURL_httpScheme() {
        XCTAssertTrue(NetworkCollector().isAllowedURL("http://jamf.example.com"),
                      "http URL should be allowed (JSS may not always have TLS in lab configs)")
    }

    func testIsAllowedURL_ftpScheme() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("ftp://files.example.com"),
                       "ftp URL should be blocked")
    }

    func testIsAllowedURL_emptyString() {
        XCTAssertFalse(NetworkCollector().isAllowedURL(""),
                       "Empty string should be blocked")
    }

    func testIsAllowedURL_fileScheme() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("file:///etc/passwd"),
                       "file:// URL should be blocked")
    }

    func testIsAllowedURL_cloudMetadataIPv4() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("https://169.254.169.254/latest/meta-data"),
                       "Cloud metadata IP 169.254.169.254 must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_cloudMetadataRange() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("https://169.254.1.1/"),
                       "Any 169.254.x.x address must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_googleMetadata() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("https://metadata.google.internal/computeMetadata"),
                       "Google metadata endpoint must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_localhost() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("http://localhost/admin"),
                       "localhost must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_loopbackIPv4() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("http://127.0.0.1/internal"),
                       "127.0.0.1 must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_loopbackIPv4Range() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("http://127.1.2.3/"),
                       "Any 127.x.x.x address must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_loopbackIPv6() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("http://[::1]/internal"),
                       "IPv6 loopback ::1 must be blocked (SSRF guard)")
    }

    func testIsAllowedURL_emptyHost() {
        XCTAssertFalse(NetworkCollector().isAllowedURL("http:///path"),
                       "URL with empty host must be blocked")
    }

    // MARK: - Finding: resilient severity/confidence fallback

    // TS-4: Renamed from testExtractJSONFencedCodeBlock to better reflect what's
    // actually being tested (resilient severity fallback, not JSON extraction).
    func testFindingUnknownSeverityFallsBackToInfo() {
        // Test via the public analyze path isn't feasible without a live API key;
        // verify structural resilience by asserting HTMLReporter/TerminalReporter
        // survive an AnalysisReport with an unknown severity string.
        let report = AnalysisReport(
            findings: [
                Finding(
                    severity: "superseverity",
                    area: "ad",
                    title: "Test finding",
                    rootCause: "Unknown cause",
                    remediationSteps: ["Step 1"],
                    confidence: "veryconfident"
                )
            ],
            summary: "Test",
            generatedAt: Date()
        )
        // resolvedSeverity/resolvedConfidence should fall back gracefully
        XCTAssertEqual(report.findings[0].resolvedSeverity,   .info,
                       "Unknown severity should fall back to .info")
        XCTAssertEqual(report.findings[0].resolvedConfidence, .inferred,
                       "Unknown confidence should fall back to .inferred")
    }

    // MARK: - CertCollector: extractPEMs (TS-6)

    func testExtractPEMsMalformedChain() {
        let collector = CertCollector()
        // A chain with a nested BEGIN (missing END before the second BEGIN)
        let malformed = """
        -----BEGIN CERTIFICATE-----
        MIIC+TCCAeGgAwIBAgIJAExample
        -----BEGIN CERTIFICATE-----
        MIIC+TCCAeGgAwIBAgIJASecond
        -----END CERTIFICATE-----
        """
        let (pems, hadMalformed) = collector.extractPEMs(from: malformed)
        XCTAssertTrue(hadMalformed,
                      "Should detect malformed chain (nested BEGIN without END)")
        XCTAssertEqual(pems.count, 1,
                       "Only the complete PEM block should be extracted")
    }

    func testExtractPEMsValidChain() {
        // CT2: A valid two-cert chain; both blocks should be extracted without malformed flag.
        let chain = """
        -----BEGIN CERTIFICATE-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAexample1placeholder==
        -----END CERTIFICATE-----
        -----BEGIN CERTIFICATE-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAexample2placeholder==
        -----END CERTIFICATE-----
        """
        let (pems, foundMalformedBlock) = CertCollector().extractPEMs(from: chain)
        XCTAssertEqual(pems.count, 2, "Should extract exactly two PEM blocks")
        XCTAssertFalse(foundMalformedBlock, "A valid chain should not set the malformed flag")
    }

    func testExtractPEMsEmpty() {
        // CT3: Empty input should produce empty output without malformed flag.
        let (pems, foundMalformedBlock) = CertCollector().extractPEMs(from: "")
        XCTAssertTrue(pems.isEmpty, "Empty input should yield no PEM blocks")
        XCTAssertFalse(foundMalformedBlock, "Empty input should not set the malformed flag")
    }

    // MARK: - ClockCollector: NTP override (CT4)

    // CT4: Sets process-global env var; XCTest does not guarantee serial execution
    // within a class. If flakiness is observed, move to a dedicated serial queue.
    func testClockCollectorUsesNTPOverride() async {
        setenv("SPACEJAMF_NTP_SERVER", "time.example.com", 1)
        defer { unsetenv("SPACEJAMF_NTP_SERVER") }
        let result = await ClockCollector().collect()
        XCTAssertEqual(result.area, .clock)
        XCTAssertTrue(
            result.rawOutput.contains("time.example.com"),
            "rawOutput should reference the injected NTP server name, got: \(result.rawOutput.prefix(200))"
        )
    }

    // MARK: - ADCollector: injectable hostname (CT5)

    func testADCollectorInjectableHostname() async {
        var collector = ADCollector()
        collector.hostname = "TESTMAC01"
        let result = await collector.collect()
        XCTAssertEqual(result.area, .ad)
        // The injected hostname must appear in the dscl section header.
        XCTAssertTrue(
            result.rawOutput.contains("dscl . -read /Computers/TESTMAC01"),
            "dscl section header should reference the injected hostname, got: \(result.rawOutput.prefix(300))"
        )
        // dscl will fail against a non-existent computer record (expected in a
        // test environment), but the section must still be present in output.
        XCTAssertTrue(
            result.rawOutput.contains("TESTMAC01"),
            "rawOutput must contain the injected hostname"
        )
    }
}
