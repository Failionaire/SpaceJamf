import XCTest
@testable import SpaceJamf

final class ScrubberTests: XCTestCase {

    // MARK: - IPv4

    func testScrubsIPv4AddressInline() {
        let output = Scrubber.scrub("Connected to 192.168.1.100 via gateway 10.0.0.1")
        XCTAssertFalse(output.contains("192.168.1.100"))
        XCTAssertFalse(output.contains("10.0.0.1"))
        XCTAssertTrue(output.contains("[IP_REDACTED]"))
    }

    func testScrubsLoopbackAddress() {
        let output = Scrubber.scrub("Listening on 127.0.0.1:8080")
        XCTAssertFalse(output.contains("127.0.0.1"))
    }

    func testPreservesNonIPNumbers() {
        // Version numbers and similar numeric strings must not be redacted
        let input  = "macOS 14.3.1 build 23D60"
        let output = Scrubber.scrub(input)
        XCTAssertEqual(output, input)
    }

    // MARK: - Credentials

    func testScrubsPasswordLine() {
        let input = """
        username: jdoe
        password: SuperSecret123!
        domain: corp.example.com
        """
        let output = Scrubber.scrub(input)
        XCTAssertFalse(output.contains("SuperSecret123"))
        XCTAssertTrue(output.contains("[CREDENTIAL_REDACTED]"))
    }

    func testScrubsPasswordCaseInsensitive() {
        let output = Scrubber.scrub("Password: abc123")
        XCTAssertFalse(output.contains("abc123"))
    }

    func testPreservesUsernameLines() {
        let input  = "username: jdoe"
        let output = Scrubber.scrub(input)
        // Username lines must not be redacted
        XCTAssertTrue(output.contains("username: jdoe"))
    }

    // MARK: - Kerberos

    func testScrubsLongBase64BlobAfterKeyword() {
        let input = "Ticket: YIIBpAYJKoZIhvcSAQICAQBuggGTMIIBj6ADAgEFoQ8bDUNPUlAuRVhBTVBMRQ=="
        let output = Scrubber.scrub(input)
        XCTAssertFalse(output.contains("YIIBpAYJKoZIhvcSAQICAQBuggGT"))
    }

    // MARK: - Structure preservation

    func testPreservesADDomainName() {
        let input  = "Active Directory Domain = corp.example.com"
        let output = Scrubber.scrub(input)
        XCTAssertTrue(output.contains("corp.example.com"))
        XCTAssertTrue(output.contains("Active Directory Domain"))
    }

    func testPreservesComputerAccountName() {
        let input  = "Computer Account = MACBOOK01$"
        let output = Scrubber.scrub(input)
        XCTAssertTrue(output.contains("MACBOOK01$"))
    }

    func testPreservesExitCodeLines() {
        let input  = "Exit Codes: dsconfigad: 0  klist: 1"
        let output = Scrubber.scrub(input)
        XCTAssertTrue(output.contains("Exit Codes"))
    }

    // MARK: - Idempotency

    func testScrubIsIdempotent() {
        let input   = "IP: 192.168.0.1  password: secret"
        let once    = Scrubber.scrub(input)
        let twice   = Scrubber.scrub(once)
        XCTAssertEqual(once, twice)
    }

    // MARK: - Empty / edge cases

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(Scrubber.scrub(""), "")
    }

    func testNoSensitiveDataUnchanged() {
        let input = "Network Time: On\nNetwork Time Server: time.apple.com"
        XCTAssertEqual(Scrubber.scrub(input), input)
    }

    // MARK: - Password pattern variants (M-8)

    func testScrubsAllCapsPasswordColon() {
        let output = Scrubber.scrub("PASSWORD: SomeSecret")
        XCTAssertFalse(output.contains("SomeSecret"),
                       "All-caps PASSWORD: should be redacted")
        XCTAssertTrue(output.contains("[CREDENTIAL_REDACTED]"))
    }

    func testScrubsMixedCasePasswordColon() {
        let output = Scrubber.scrub("passwOrd: SomeSecret")
        XCTAssertFalse(output.contains("SomeSecret"),
                       "Mixed-case passwOrd: should be redacted")
        XCTAssertTrue(output.contains("[CREDENTIAL_REDACTED]"))
    }

    func testScrubsPasswordEqualsLower() {
        let output = Scrubber.scrub("password = SuperSecret")
        XCTAssertFalse(output.contains("SuperSecret"),
                       "password = value form should be redacted")
        XCTAssertTrue(output.contains("[CREDENTIAL_REDACTED]"))
    }

    func testScrubsPasswordEqualsAllCaps() {
        let output = Scrubber.scrub("PASSWORD = SuperSecret")
        XCTAssertFalse(output.contains("SuperSecret"),
                       "PASSWORD = value with all-caps should be redacted")
        XCTAssertTrue(output.contains("[CREDENTIAL_REDACTED]"))
    }

    // MARK: - IPv6 scrubbing (NEW-14)

    func testScrubsFullFormIPv6() {
        let output = Scrubber.scrub("Address: 2001:0db8:0000:0000:0000:0000:0000:7334")
        XCTAssertFalse(output.contains("2001:0db8"),
                       "Full 8-group IPv6 should be redacted")
        XCTAssertTrue(output.contains("[IP_REDACTED]"))
    }

    func testScrubsCompressedIPv6() {
        let output = Scrubber.scrub("Source: fe80::1")
        XCTAssertFalse(output.contains("fe80::1"),
                       "Compressed IPv6 fe80::1 should be redacted")
        XCTAssertTrue(output.contains("[IP_REDACTED]"))
    }

    func testScrubsLoopbackIPv6() {
        let output = Scrubber.scrub("Loopback: ::1")
        XCTAssertFalse(output.contains("::1"),
                       "IPv6 loopback ::1 should be redacted")
        XCTAssertTrue(output.contains("[IP_REDACTED]"))
    }
}
