# Contributing to SpaceJamf

Thanks for your interest in contributing. This is a focused tool, so please read this before opening a PR.

---

## Ground Rules

- **Security first.** SpaceJamf handles sensitive diagnostic data. Any change that touches data collection, scrubbing, or transmission to the Claude API gets extra scrutiny. If you're unsure, open an issue to discuss before writing code.
- **Keep the scrubber honest.** If you add a new collector that may surface sensitive data (IPs, credentials, tokens), update `Scrubber.swift` and add a test in `ScrubberTests.swift` that proves the sensitive value is absent from `scrubbedOutput`.
- **No raw output leaves the device.** `rawOutput` on `DiagnosticResult` must never be passed to `ClaudeClient` or written to an output file. This is a hard invariant enforced at the type level: `scrubbedOutput` is `private(set)` and can only be populated via `DiagnosticResult.withScrubbedOutput(_:)`, ensuring every write goes through the scrubber. CT-2: Any refactor that removes or weakens this protection will be rejected.
- **Scope.** Don't add features not in the roadmap without opening an issue first. The project's value comes from being focused and trustworthy, not from having the most flags.

---

## Development Setup

Requires macOS 13+, Swift 5.7+ (Xcode 14+).

```bash
git clone https://github.com/Failionaire/SpaceJamf.git
cd SpaceJamf
# CT-1: Build with strict concurrency to catch Sendable and actor-isolation issues at compile time.
swift build -Xswiftc -strict-concurrency=complete
swift test
```

For a full run without an API key:

```bash
sudo .build/debug/spacejamf diagnose --no-claude
```

To inspect what would be sent to Claude without making a network call:

```bash
sudo .build/debug/spacejamf diagnose --dry-run
```

---

## Project Layout

```
Sources/SpaceJamf/
├── Commands/        # CLI subcommands (ArgumentParser)
├── Collectors/      # One file per diagnostic area; implements CollectorProtocol
├── Scrubber/        # Regex-based redaction; must have test coverage
├── Analyzer/        # Claude API client, prompt builder, response models
├── Reporters/       # Terminal (ANSI) and HTML output
├── Models/          # Shared value types
└── Utilities/       # Shell process wrapper, config loader
```

---

## Adding a New Collector

1. Create `Sources/SpaceJamf/Collectors/YourCollector.swift` implementing `CollectorProtocol`:

```swift
struct YourCollector: CollectorProtocol {
    var requiresElevation: Bool { false } // set true only if strictly necessary

    func collect() async -> DiagnosticResult {
        // Use Shell.run() — do not use system(), popen(), or shell injection patterns
    }
}
```

2. Register it in `DiagnoseCommand.swift` and add it to the `DiagnosticArea` enum.
3. Add a fixture file under `Tests/SpaceJamfTests/Fixtures/`.
4. Add a fixture-based test in `CollectorTests.swift`.
5. If the output may contain sensitive values, add scrubber patterns and tests.

---

## Adding Scrubber Patterns

All patterns live in `Scrubber.swift`. Every new pattern needs a corresponding test in `ScrubberTests.swift` that:

1. Provides input containing the sensitive value verbatim.
2. Asserts the value is **absent** from `scrub()` output.
3. Asserts a reasonable placeholder (`[IP_REDACTED]`, etc.) is present.

---

## Testing

```bash
swift test
```

All tests are fixture-based — no real Jamf or AD environment is required. Tests must pass on a development Mac without elevated privileges.

---

## Code Style

A `.swiftformat` configuration file is included in the repository root. Run `swiftformat .` before committing to enforce consistent formatting.

---

## Pull Request Checklist

- [ ] `swift build -Xswiftc -strict-concurrency=complete` passes with no warnings
- [ ] `swift test` passes
- [ ] Any new collector includes fixture + test
- [ ] Any new scrubber pattern includes a test asserting the sensitive value is absent
- [ ] No `rawOutput` is passed to `ClaudeClient` or written to output files
- [ ] PR description explains *what* changed and *why*

---

## Reporting Bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) if one exists,
or open a plain GitHub issue. Please redact any sensitive data before pasting command
output — the issue tracker is public.

---

## Suggesting Features

Open a [feature request](.github/ISSUE_TEMPLATE/feature_request.md) (or a plain issue)
before writing code. The v2 roadmap item (`--explain <finding-id>`) is already planned;
smaller scoped ideas are very welcome.


