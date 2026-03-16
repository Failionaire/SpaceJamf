import Foundation

enum PromptBuilder {

    // MARK: - System prompt

    static let systemPrompt = """
    You are an expert macOS, Jamf Pro, and Active Directory systems administrator with \
    deep knowledge of Kerberos, certificate management, DNS, and Apple MDM.

    Analyze the diagnostic output provided and identify issues. Return ONLY a valid JSON \
    object — no markdown, no code fences, no explanation outside the JSON.

    Required JSON structure:
    {
      "summary": "<one or two sentence overall assessment>",
      "findings": [
        {
          "severity": "critical|warning|info",
          "area": "ad|jamf|certs|network|clock",
          "title": "<concise issue title>",
          "root_cause": "<detailed root cause explanation>",
          "remediation_steps": ["step 1", "step 2"],
          "confidence": "certain|inferred"
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

    // MARK: - Build

    /// Assembles the user-facing Claude prompt from scrubbed diagnostic results.
    /// Also fetches `sw_vers` and `uname -m` to give Claude system context.
    static func build(from results: [DiagnosticResult]) async -> (system: String, user: String) {
        // Gather system context concurrently with a small task group
        async let swVers = Shell.run("/usr/bin/sw_vers", args: [])
        async let uname  = Shell.run("/usr/bin/uname",  args: ["-m"])

        let (swVersResult, unameResult) = await (swVers, uname)

        var sections: [String] = []

        sections.append("""
        ## System Context
        \(swVersResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        Architecture: \(unameResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        """)

        for result in results.sorted(by: { $0.area.rawValue < $1.area.rawValue }) {
            let exitSummary = result.exitCodes
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")

            sections.append("""
            ## \(result.area.rawValue.uppercased()) Diagnostic
            Exit Codes: \(exitSummary.isEmpty ? "none" : exitSummary)

            \(result.scrubbedOutput ?? "")
            """)
        }

        // NOTE: scrubbed diagnostic output is embedded verbatim from local system commands.
        // If future versions support external file input, apply a per-section size clamp
        // (e.g. 8 KB) to limit prompt-injection blast radius before that feature ships.
        let userPrompt = sections.joined(separator: "\n\n---\n\n")
        return (system: systemPrompt, user: userPrompt)
    }
}
