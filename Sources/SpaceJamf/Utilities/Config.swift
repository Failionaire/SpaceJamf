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

        if FileManager.default.fileExists(atPath: configFileURL.path),
           let contents = try? String(contentsOf: configFileURL, encoding: .utf8) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: configFileURL.path),
               let perms = attrs[.posixPermissions] as? Int,
               perms & 0o077 != 0 {
                fputs("Warning: ~/.spacejamf/config has insecure permissions. Run: chmod 600 \(configFileURL.path)\n", stderr)
            }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == "ANTHROPIC_API_KEY" {
                    return parts[1]
                }
            }
        }

        throw ConfigError.missingAPIKey
    }

    // MARK: - Model

    /// Returns the model to use for Claude requests.
    static func model() -> String {
        ProcessInfo.processInfo.environment["SPACEJAMF_MODEL"] ?? defaultModel
    }
}

// MARK: - Errors

enum ConfigError: Error, CustomStringConvertible {
    case missingAPIKey

    var description: String {
        """
        Anthropic API key not found.

        Provide it via environment variable:
          export ANTHROPIC_API_KEY=sk-ant-...

        Or add it to ~/.spacejamf/config:
          ANTHROPIC_API_KEY=sk-ant-...

        Run with --no-claude to skip AI analysis entirely.
        """
    }
}
