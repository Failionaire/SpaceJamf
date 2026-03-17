/// Assembles the system and user prompts sent to Claude from DiagnosticResult data.
import Foundation

// MARK: - AnalysisPrompt

/// Typed container for the system and user prompt strings passed to ClaudeClient.
struct AnalysisPrompt: Sendable {
    let system: String
    let user: String
}

// MARK: - PromptBuilder

enum PromptBuilder {

    // MARK: - System prompt

    static let systemPrompt: String = {
        // Build the allowed severity list dynamically from the Severity enum so a
        // future case addition stays in sync automatically (FI-2).
        let severityList = Severity.allCases.map(\.rawValue).joined(separator: "|")
        let confidenceList = Confidence.allCases.map(\.rawValue).joined(separator: "|")
        return """
        You are an expert macOS, Jamf Pro, and Active Directory systems administrator with \
        deep knowledge of Kerberos, certificate management, DNS, and Apple MDM.

        Analyze the diagnostic output provided and identify issues. Return ONLY a valid JSON \
        object — no markdown, no code fences, no explanation outside the JSON.

        Required JSON structure:
        {
          "summary": "<one or two sentence overall assessment>",
          "findings": [
            {
              "severity": "\(severityList)",
              "area": "ad|jamf|certs|network|clock",
              "title": "<concise issue title>",
              "root_cause": "<detailed root cause explanation>",
              "remediation_steps": ["step 1", "step 2"],
              "confidence": "\(confidenceList)"
            }
          ]
        }

        Rules:
        - Sort findings by severity descending (critical → warning → info).
        - Use "certain" when the output clearly demonstrates the issue.
        - Use "inferred" when you are deducing from indirect evidence.
        - Only include findings that represent actionable issues. Omit areas where output \
          indicates everything is healthy.
        - remediation_steps must be an array of strings even when there is only one step.
        """
    }()

    // MARK: - Cached system context

    /// Caches sw_vers and uname -m output so repeated build() calls in the same
    /// process do not re-spawn the binaries each time.
    private actor SystemContextCache {
        var swVers: String?
        var uname: String?

        func swVersOutput() async -> String {
            if let cached = swVers { return cached }
            let result = await Shell.run("/usr/bin/sw_vers", args: [])
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            swVers = output
            return output
        }

        func unameOutput() async -> String {
            if let cached = uname { return cached }
            let result = await Shell.run("/usr/bin/uname", args: ["-m"])
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            uname = output
            return output
        }
    }

    private static let systemContextCache = SystemContextCache()

    // 8 KB per section × 5 areas ≈ 42 KB total, comfortably within Claude's 200K context window.
    // Note: The Anthropic API's system/user separation provides the primary isolation boundary
    // against prompt injection. sectionSizeLimit is a secondary mitigation that limits the
    // blast radius from adversarial tool output attempting to override instructions.
    private static let sectionSizeLimit = 8 * 1024

    // MARK: - Build

    /// Assembles the user-facing Claude prompt from scrubbed diagnostic results.
    /// Also fetches `sw_vers` and `uname -m` to give Claude system context.
    /// Returns `nil` when `results` is empty so callers can skip a wasted API call.
    static func build(from results: [DiagnosticResult]) async -> AnalysisPrompt? {
        guard !results.isEmpty else { return nil }
        async let swVers = systemContextCache.swVersOutput()
        async let uname  = systemContextCache.unameOutput()
        let (swVersOutput, unameOutput) = await (swVers, uname)

        // Use fallback labels when commands are unavailable (e.g. sandboxed environments)
        // so Claude doesn't silently assume defaults for OS version or architecture.
        let swVersLine = swVersOutput.isEmpty ? "(unavailable)" : swVersOutput
        let unameLine  = unameOutput.isEmpty  ? "(unavailable)" : unameOutput

        var sections: [String] = []

        sections.append("""
        ## System Context
        \(swVersLine)
        Architecture: \(unameLine)
        """)

        // Alphabetical order gives Claude a consistent section layout across runs.
        for result in results.sorted(by: { $0.area.rawValue < $1.area.rawValue }) {
            let exitSummary = result.exitCodes
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")

            guard let raw = result.scrubbedOutput else {
                preconditionFailure("DiagnosticResult for \(result.area.rawValue) has no scrubbedOutput — Scrubber must run before PromptBuilder")
            }
            let clampedRaw = raw.count <= sectionSizeLimit
                ? raw
                : String(raw.prefix(sectionSizeLimit)) + "\n… [output truncated at 8 KB]"

            sections.append("""
            ## \(result.area.displayName) Diagnostic
            Exit Codes: \(exitSummary.isEmpty ? "none" : exitSummary)

            \(clampedRaw)
            """)
        }

        let userPrompt = sections.joined(separator: "\n\n---\n\n")
        return AnalysisPrompt(system: systemPrompt, user: userPrompt)
    }
}
