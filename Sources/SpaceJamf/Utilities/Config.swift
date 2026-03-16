import Foundation

enum Config {
    /// Default model used for Claude analysis. Override with `SPACEJAMF_MODEL`.
    static let defaultModel = "claude-sonnet-4-6"

    private static var configFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".spacejamf")
            .appendingPathComponent("config")
    }

    // MARK: - API Key

    /// Resolves the Anthropic API key.
    /// Resolution order:
    ///   1. `ANTHROPIC_API_KEY` environment variable
    ///   2. `ANTHROPIC_API_KEY=…` line in `~/.spacejamf/config`
    ///
    /// Throws `ConfigError.missingAPIKey` with a helpful message when neither source is found.
    static func anthropicAPIKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !key.isEmpty {
            return key
        }

        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            throw ConfigError.missingAPIKey
        }

        let contents: String
        do {
            // Check permissions before reading
            if let attrs = try? FileManager.default.attributesOfItem(atPath: configFileURL.path),
               let perms = attrs[.posixPermissions] as? Int,
               perms & 0o077 != 0 {
                err("Warning: ~/.spacejamf/config has insecure permissions. Run: chmod 600 \(configFileURL.path)")
            }
            contents = try String(contentsOf: configFileURL, encoding: .utf8)
        } catch {
            throw ConfigError.configFileUnreadable(configFileURL.path, error)
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "ANTHROPIC_API_KEY" {
                // Strip a single matching pair of " or ' delimiters (L-17).
                var value = parts[1]
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'")  && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                return value
            }
        }

        throw ConfigError.missingAPIKey
    }

    // MARK: - Model

    /// Returns the model to use for Claude requests.
    /// Warns to stderr if the value does not look like a Claude model name (NEW-3).
    static func model() -> String {
        let m = ProcessInfo.processInfo.environment["SPACEJAMF_MODEL"] ?? defaultModel
        if !m.hasPrefix("claude-") {
            err("Warning: SPACEJAMF_MODEL='\(m)' does not start with 'claude-' — this may cause a 400 API error")
        }
        return m
    }

    // MARK: - Max tokens

    /// Returns the max_tokens value for Claude requests.
    /// Override with `SPACEJAMF_MAX_TOKENS`. Defaults to 4096.
    static func maxTokens() -> Int {
        if let str = ProcessInfo.processInfo.environment["SPACEJAMF_MAX_TOKENS"],
           let value = Int(str), value > 0 {
            return value
        }
        return 4096
    }
}

// MARK: - Errors

enum ConfigError: Error, CustomStringConvertible {
    case missingAPIKey
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
        case .configFileUnreadable(let path, let error):
            return "Could not read config file at \(path): \(error.localizedDescription)"
        }
    }
}
