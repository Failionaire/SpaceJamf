import Foundation

enum Config {
    /// Default model used for Claude analysis. Override with `SPACEJAMF_MODEL`.
    static let defaultModel = "claude-sonnet-4-6"

    // CF2: stored let — homeDirectoryForCurrentUser is stable for the process lifetime.
    private static let configFileURL: URL =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spacejamf/config")

    // MARK: - API Key

    /// Resolves the Anthropic API key.
    /// Resolution order:
    ///   1. `ANTHROPIC_API_KEY` environment variable
    ///   2. `ANTHROPIC_API_KEY=…` line in `~/.spacejamf/config`
    ///
    /// Throws `ConfigError.missingAPIKey` with a helpful message when neither source is found.
    static func anthropicAPIKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            let trimmed = key.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw ConfigError.missingAPIKey }
            guard trimmed.hasPrefix("sk-ant-") else { throw ConfigError.invalidAPIKey(trimmed) }
            return trimmed
        }

        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            throw ConfigError.missingAPIKey
        }

        let contents: String
        do {
            // Check permissions before reading; warn if the file is world/group readable.
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: configFileURL.path)
                if let perms = attrs[.posixPermissions] as? Int, perms & 0o077 != 0 {
                    err("Warning: ~/.spacejamf/config has insecure permissions. Run: chmod 600 \(configFileURL.path)")
                }
            } catch {
                // CF3: String(describing:) gives reproducible English output regardless of locale.
                err("Warning: could not check permissions on config file: \(String(describing: error))")
            }
            contents = try String(contentsOf: configFileURL, encoding: .utf8)
        } catch {
            throw ConfigError.configFileUnreadable(configFileURL.path, error)
        }

        // CF1: Collect all matches to detect and warn on duplicate keys while using the first.
        var foundValue: String? = nil
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "ANTHROPIC_API_KEY" else { continue }
            // Strip a single matching pair of " or ' delimiters.
            var value = parts[1]
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'")  && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if foundValue != nil {
                err("Warning: duplicate key 'ANTHROPIC_API_KEY' in config file — using first value")
                continue
            }
            foundValue = value
        }

        if let value = foundValue {
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ConfigError.missingAPIKey
            }
            guard value.hasPrefix("sk-ant-") else {
                throw ConfigError.invalidAPIKey(value)
            }
            return value
        }

        throw ConfigError.missingAPIKey
    }

    // MARK: - Model

    /// Returns the model to use for Claude requests.
    /// Resolution order:
    ///   1. `SPACEJAMF_MODEL` environment variable
    ///   2. `SPACEJAMF_MODEL=…` line in `~/.spacejamf/config`
    ///   3. `defaultModel` constant
    ///
    /// Warns to stderr if the resolved model does not look like a Claude model name.
    static func model() -> String {
        // env var takes precedence; config file is the secondary source (CF4).
        let m: String
        if let envValue = ProcessInfo.processInfo.environment["SPACEJAMF_MODEL"] {
            m = envValue.trimmingCharacters(in: .whitespaces)
        } else if let fileValue = readConfigFileValue(forKey: "SPACEJAMF_MODEL"),
                  !fileValue.trimmingCharacters(in: .whitespaces).isEmpty {
            m = fileValue.trimmingCharacters(in: .whitespaces)
        } else {
            return defaultModel
        }
        if !m.hasPrefix("claude-") {
            err("Warning: SPACEJAMF_MODEL='\(m)' does not start with 'claude-' — this may cause a 400 API error")
        }
        return m
    }

    // MARK: - Max tokens

    /// Returns the max_tokens value for Claude requests.
    /// Override with `SPACEJAMF_MAX_TOKENS`. Defaults to 4096.
    static func maxTokens() -> Int {
        // CF5: 16 384 is a conservative upper bound compatible with current Claude models.
        // Revisit if the default model or its output-token limit changes significantly.
        let maxAllowed = 16_384
        if let str = ProcessInfo.processInfo.environment["SPACEJAMF_MAX_TOKENS"] {
            guard let value = Int(str), value > 0 else {
                err("Warning: SPACEJAMF_MAX_TOKENS='\(str)' is not a positive integer — using default 4096")
                return 4096
            }
            if value > maxAllowed {
                err("Warning: SPACEJAMF_MAX_TOKENS=\(value) exceeds the maximum \(maxAllowed) — clamping.")
                return maxAllowed
            }
            return value
        }
        return 4096
    }

    // MARK: - Private helpers

    /// Reads the first `key=value` pair for `key` from the config file, stripping
    /// optional quote delimiters. Returns nil if the file is absent, unreadable,
    /// or the key is not present. Does not perform permission checks.
    private static func readConfigFileValue(forKey key: String) -> String? {
        guard FileManager.default.fileExists(atPath: configFileURL.path),
              let contents = try? String(contentsOf: configFileURL, encoding: .utf8) else {
            return nil
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == key else { continue }
            var value = parts[1]
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'")  && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }
}

// MARK: - Errors

enum ConfigError: Error, CustomStringConvertible {
    case missingAPIKey
    case invalidAPIKey(String)
    case configFileUnreadable(String, Error)

    var description: String {
        switch self {
        case .missingAPIKey:
            return """
            Anthropic API key not found.

            Provide it via environment variable:
              export ANTHROPIC_API_KEY=sk-ant-...

            Or add it to ~/.spacejamf/config:
              ANTHROPIC_API_KEY=sk-ant-...

            Run with --no-claude to skip AI analysis entirely.
            """
        case .invalidAPIKey(let key):
            return "The API key appears invalid — Anthropic keys begin with 'sk-ant-'. Got: '\(key.prefix(12))…'"
        case .configFileUnreadable(let path, let error):
            // CF3: String(describing:) gives reproducible English output; localizedDescription
            // may vary by locale and sometimes omits underlying NSError detail.
            return "Could not read config file at \(path): \(String(describing: error))"
        }
    }
}
