import XCTest
@testable import SpaceJamf

final class ConfigTests: XCTestCase {

    // CT8: CAUTION — setenv/unsetenv mutate the global process environment.
    // XCTest does not isolate test processes by default; parallel execution of
    // these tests could cause flakiness if another test reads the same env var
    // concurrently. If instability is observed, apply `.serialized` test plan
    // ordering or refactor Config to accept an injected environment dictionary.

    // MARK: - API key: blank environment variable

    func testAnthropicAPIKeyRejectsBlankEnvVar() throws {
        setenv("ANTHROPIC_API_KEY", "   ", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }

        XCTAssertThrowsError(try Config.anthropicAPIKey()) { error in
            guard case ConfigError.missingAPIKey = error else {
                return XCTFail("Expected ConfigError.missingAPIKey for blank env var, got: \(error)")
            }
        }
    }

    // MARK: - API key: invalid prefix

    func testAnthropicAPIKeyRejectsKeyWithoutPrefix() throws {
        setenv("ANTHROPIC_API_KEY", "not-a-valid-key", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }

        XCTAssertThrowsError(try Config.anthropicAPIKey()) { error in
            guard case ConfigError.invalidAPIKey = error else {
                return XCTFail("Expected ConfigError.invalidAPIKey for key without 'sk-ant-' prefix, got: \(error)")
            }
        }
    }

    // MARK: - API key: valid prefix accepted

    func testAnthropicAPIKeyAcceptsValidKey() throws {
        setenv("ANTHROPIC_API_KEY", "sk-ant-test-key-01", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }

        let key = try Config.anthropicAPIKey()
        XCTAssertEqual(key, "sk-ant-test-key-01")
    }

    // MARK: - API key: leading/trailing whitespace trimmed

    func testAnthropicAPIKeyTrimsWhitespace() throws {
        setenv("ANTHROPIC_API_KEY", "  sk-ant-padded-key  ", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }

        let key = try Config.anthropicAPIKey()
        XCTAssertEqual(key, "sk-ant-padded-key",
                       "Leading and trailing whitespace should be stripped from the API key")
    }

    // MARK: - Model: default used when env var absent

    func testModelReturnsDefaultWhenNoEnvVar() {
        // Ensure the env var is not set; store and restore any existing value.
        let existing = ProcessInfo.processInfo.environment["SPACEJAMF_MODEL"]
        if existing != nil { unsetenv("SPACEJAMF_MODEL") }
        defer { if let v = existing { setenv("SPACEJAMF_MODEL", v, 1) } }

        let model = Config.model()
        XCTAssertEqual(model, Config.defaultModel,
                       "model() should return defaultModel when no env var or config file override is present")
    }

    // MARK: - Model: env var takes precedence

    func testModelReadsFromEnvVar() {
        setenv("SPACEJAMF_MODEL", "claude-opus-4-6", 1)
        defer { unsetenv("SPACEJAMF_MODEL") }

        XCTAssertEqual(Config.model(), "claude-opus-4-6")
    }

    // MARK: - Max tokens: default

    func testMaxTokensReturnsDefault() {
        let existing = ProcessInfo.processInfo.environment["SPACEJAMF_MAX_TOKENS"]
        if existing != nil { unsetenv("SPACEJAMF_MAX_TOKENS") }
        defer { if let v = existing { setenv("SPACEJAMF_MAX_TOKENS", v, 1) } }

        XCTAssertEqual(Config.maxTokens(), 4096)
    }

    // MARK: - Max tokens: invalid env var falls back to default

    func testMaxTokensIgnoresNonIntegerEnvVar() {
        setenv("SPACEJAMF_MAX_TOKENS", "notanumber", 1)
        defer { unsetenv("SPACEJAMF_MAX_TOKENS") }

        XCTAssertEqual(Config.maxTokens(), 4096,
                       "Invalid SPACEJAMF_MAX_TOKENS should fall back to default 4096")
    }

    // MARK: - Max tokens: zero rejected as non-positive

    func testMaxTokensRejectsZero() {
        setenv("SPACEJAMF_MAX_TOKENS", "0", 1)
        defer { unsetenv("SPACEJAMF_MAX_TOKENS") }

        XCTAssertEqual(Config.maxTokens(), 4096,
                       "Zero SPACEJAMF_MAX_TOKENS is not a positive integer and should fall back to 4096")
    }

    // MARK: - Max tokens: valid positive value accepted

    func testMaxTokensReturnsValidPositiveValue() {
        setenv("SPACEJAMF_MAX_TOKENS", "8192", 1)
        defer { unsetenv("SPACEJAMF_MAX_TOKENS") }

        XCTAssertEqual(Config.maxTokens(), 8192,
                       "A valid positive SPACEJAMF_MAX_TOKENS should be returned as-is")
    }

    // MARK: - Max tokens: value above cap is clamped

    func testMaxTokensClampedToMaxAllowed() {
        setenv("SPACEJAMF_MAX_TOKENS", "999999", 1)
        defer { unsetenv("SPACEJAMF_MAX_TOKENS") }

        // The internal maxAllowed is 16_384; values above it are clamped.
        XCTAssertEqual(Config.maxTokens(), 16_384,
                       "SPACEJAMF_MAX_TOKENS above the internal cap should be clamped to 16_384")
    }
}
