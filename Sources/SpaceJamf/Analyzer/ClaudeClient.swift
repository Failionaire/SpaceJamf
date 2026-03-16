import Foundation

enum ClaudeClient {

    // MARK: - Request types

    private struct RequestMessage: Encodable {
        let role: String
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
        let type: String
        let text: String?
    }

    private struct APIResponse: Decodable {
        let content: [ContentBlock]
    }

    // MARK: - Private URLSession

    /// Custom session with generous timeouts to accommodate large diagnostics payloads
    /// and long Claude inference times (M-12). URLSession.shared defaults to 60 s,
    /// which is too short for legitimate multi-area analysis calls.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// POST a prompt to the Anthropic Messages API and decode the `AnalysisReport`.
    static func analyze(
        prompt: (system: String, user: String),
        apiKey: String,
        model: String
    ) async throws -> AnalysisReport {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClaudeError.invalidConfiguration("Bad API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model:     model,
            maxTokens: Config.maxTokens(),
            system:    prompt.system,
            messages:  [RequestMessage(role: "user", content: prompt.user)]
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

        guard let textBlock = apiResponse.content.first(where: { $0.type == "text" }),
              let text = textBlock.text
        else {
            throw ClaudeError.emptyResponse
        }

        let jsonText = extractJSON(from: text)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw ClaudeError.malformedJSON(jsonText)
        }

        let decoder = JSONDecoder()
        var report = try decoder.decode(AnalysisReport.self, from: jsonData)
        report.generatedAt = Date()
        return report
    }

    // MARK: - Helpers

    /// Strips markdown code fences if present and extracts the outermost JSON object
    /// using brace-depth counting to handle nested braces in field values.
    private static func extractJSON(from text: String) -> String {
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

enum ClaudeError: Error, CustomStringConvertible {
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
            return "Anthropic API returned HTTP \(code):\n\(body.prefix(500))"
        case .emptyResponse:
            return "Claude returned an empty response."
        case .malformedJSON(let text):
            return "Could not parse Claude response as JSON:\n\(text.prefix(200))"
        }
    }
}
