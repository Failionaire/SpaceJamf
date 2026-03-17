/// Wraps the Anthropic Messages API for sending prompts and decoding AnalysisReport responses.
import Foundation

enum ClaudeClient {

    // MARK: - Constants

    // Pinned intentionally; bump when adopting new API features (e.g. extended output).
    // URL(string:) would always succeed for this literal; using URL(string:)! avoids a
    // per-call guard branch that can never actually fail.
    private static let apiURL           = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    // MARK: - Request types

    private enum Role: String, Encodable {
        case user
    }

    private struct RequestMessage: Encodable {
        let role: Role
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [RequestMessage]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
        }
    }

    // MARK: - Response types

    private struct ContentBlock: Decodable {
        // type is optional so that an API response with a missing or novel content-block
        // type field degrades gracefully rather than failing with a cryptic CodingKey error.
        let type: String?
        let text: String?
    }

    private struct APIResponse: Decodable {
        let content: [ContentBlock]
    }

    // MARK: - Private URLSession

    /// Custom session with generous timeouts to accommodate large diagnostics payloads
    /// and long Claude inference times. URLSession.shared defaults to 60 s,
    /// which is too short for legitimate multi-area analysis calls.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Validates that `key` is non-blank. Extracted from `analyze` so callers can
    /// unit-test pre-flight validation without making a network call.
    static func validateAPIKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ClaudeError.invalidConfiguration("API key is empty")
        }
    }

    /// POST a prompt to the Anthropic Messages API and decode the `AnalysisReport`.
    static func analyze(
        prompt: AnalysisPrompt,
        apiKey: String,
        model: String
    ) async throws -> AnalysisReport {
        // Pre-flight: reject blank keys locally rather than wasting a network round-trip.
        try validateAPIKey(apiKey)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,              forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion,    forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model:     model,
            maxTokens: Config.maxTokens(),
            system:    prompt.system,
            messages:  [RequestMessage(role: .user, content: prompt.user)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(unreadable)"
            throw ClaudeError.apiError(statusCode: http.statusCode, body: body)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let textBlock = apiResponse.content.first(where: { $0.type == "text" || $0.type == nil }),
              let text = textBlock.text
        else {
            throw ClaudeError.emptyResponse
        }

        let jsonText = extractJSON(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw ClaudeError.malformedJSON(jsonText)
        }

        do {
            let report = try AnalysisReport.decoder.decode(AnalysisReport.self, from: jsonData)
            return report.withGeneratedAt(Date())
        } catch {
            // Include the original DecodingError description (which contains the failing
            // CodingKey path, e.g. findings[0].severity) alongside the raw JSON text so
            // prompt/schema mismatches are immediately diagnosable.
            throw ClaudeError.malformedJSON("\(jsonText)\n[Decoding error: \(error.localizedDescription)]")
        }
    }

    // MARK: - Helpers

    /// Strips markdown code fences if present and extracts the outermost JSON object
    /// using brace-depth counting to handle nested braces in field values.
    /// Exposed as internal for test access.
    ///
    /// - Note: The brace-depth counter operates on raw characters, not parsed tokens.
    ///   A JSON string value that contains an *unbalanced* `{` or `}` (e.g.
    ///   `"root_cause": "missing }"`) can cause premature extraction termination.
    ///   Balanced braces inside string values (e.g. `"{foo}"`) are handled correctly
    ///   because depth increments and decrements cancel out. This heuristic is
    ///   sufficient for Claude's structured JSON output in practice.
    static func extractJSON(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ``` or ```json fences
        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: .newlines)
            lines.removeFirst() // opening fence line (e.g. ```json)
            // Remove trailing closing fence, skipping any blank lines after it
            while let last = lines.last {
                let stripped = last.trimmingCharacters(in: .whitespaces)
                if stripped == "```" {
                    lines.removeLast()
                    break
                } else if stripped.isEmpty {
                    lines.removeLast()
                } else {
                    break
                }
            }
            trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find outermost { … } using brace-depth counting so that nested braces
        // inside root_cause or remediation_steps text don't end the match prematurely.
        guard let start = trimmed.firstIndex(of: "{") else { return trimmed }
        var depth = 0
        var endIndex: String.Index? = nil
        outer: for idx in trimmed[start...].indices {
            switch trimmed[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    endIndex = idx
                    break outer
                }
            default: break
            }
        }
        if let end = endIndex {
            return String(trimmed[start...end])
        }
        return trimmed
    }
}

// MARK: - Errors

enum ClaudeError: Error, Sendable, CustomStringConvertible {
    case invalidConfiguration(String)
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case emptyResponse
    case malformedJSON(String)

    var description: String {
        switch self {
        case .invalidConfiguration(let msg):
            return "Configuration error: \(msg)"
        case .invalidResponse:
            return "Received a non-HTTP response from the Anthropic API."
        case .apiError(let code, let body):
            if code == 429 {
                return "Anthropic API rate limit hit (HTTP 429). Wait a moment and retry.\n\(body.prefix(200))"
            }
            return "Anthropic API returned HTTP \(code):\n\(body.prefix(500))"
        case .emptyResponse:
            return "Claude returned an empty response."
        case .malformedJSON(let text):
            return "Could not parse Claude response as JSON:\n\(text.prefix(200))"
        }
    }
}
