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
}
