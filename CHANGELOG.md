# Changelog

All notable changes to SpaceJamf will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

---

## [0.1.0-beta.1] — 2026-03-17

### Added
- Initial project structure and architecture
- `CollectorProtocol` with `requiresElevation` pre-flight checking
- `ADCollector` — Active Directory binding diagnostics via `dsconfigad`, `klist`, `dscl`; injectable `hostname` property for unit testing
- `JamfCollector` — JSS connectivity and MDM profile checks; injectable `jamfPath` for unit testing
- `CertCollector` — certificate validity and chain checks via `openssl x509`, with batched parallel inspection and malformed-block detection
- `NetworkCollector` — DNS resolution and JSS reachability; injectable `adDomain`/`jssURL` for unit testing
- `ClockCollector` — NTP sync and clock skew detection; injectable NTP server via `SPACEJAMF_NTP_SERVER`
- `Scrubber` — regex-based redaction of IPv4/IPv6 addresses, MAC addresses, Kerberos ticket blobs, and credential lines
- `ClaudeClient` — async Anthropic Messages API integration via `URLSession` with configurable timeouts
- `PromptBuilder` — structured prompt assembly with OS context; 8 KB per-section cap to limit prompt injection blast radius
- `TerminalReporter` — ANSI severity badges, confidence indicators, and `NO_COLOR` support
- `HTMLReporter` — self-contained single-file HTML report with keyboard-accessible collapsible findings
- `--no-claude` flag for offline / API-key-free usage
- `--dry-run` flag to inspect scrubbed payload without making API calls
- `--areas` flag to limit collection to specific diagnostic areas
- `--output-format html` flag to generate a shareable HTML report
- `--save-json` flag to persist an analysis report for later re-rendering
- `--output-dir` flag to specify the directory for HTML output files
- `spacejamf report` subcommand to re-render saved JSON reports
- `Config` — API key resolution from env var or `~/.spacejamf/config`, with permission warnings; model and max-tokens overrides

### Fixed
- `CertCollector`: `hadMalformed` variable was undeclared (compile error)
- `ADCollector`: two statements were squashed on one line (CRLF source issue)
- `ClaudeClient`: blank or whitespace-only API key no longer silently proceeds
- `ClaudeClient`: response now decoded with the shared `AnalysisReport.decoder` (ISO 8601 date strategy) for consistency
- `DiagnoseCommand`: UUID-based HTML filenames replaced with ISO 8601 timestamps
- `DiagnoseCommand`: `Config.model()` captured once to prevent silent divergence between the log message and the API call
- `ReportCommand`: fabricated timestamp on loaded reports removed
- `ReportCommand`: TOCTOU `fileExists` pre-check replaced with direct read error handling
- `Scrubber`: password regex tightened to require `=` or `:` separator, avoiding false positives on policy description lines
- `JamfCollector`: `jamfPath` changed from `var` to `init` parameter to prevent accidental mutation
- `ClockCollector`: force-unwrap on `Int(epochStr)` replaced with safe `if let`
- `TerminalReporter`: trailing newlines trimmed from raw collector output
- `Config`: stale internal comment referencing a specific model name removed

### Security
- `HTMLReporter`: severity field was interpolated into HTML without escaping (XSS vector); now escaped via `esc()`
- `HTMLReporter`: `tabindex="0"` added directly to finding headers so keyboard focus works without JavaScript
- `Config`: `sk-ant-` prefix validation added; placeholder/typo API keys are rejected before any network call
- `Config`: max-tokens value clamped at 16,384 to prevent accidental overspend
- `HTMLReporter`: Content-Security-Policy `<meta>` tag added to generated reports
- `Shell`: `SIGPIPE` suppression added to prevent broken-pipe signals from killing the main process
- `NetworkCollector`: SSRF guard extended to block `localhost`, `127.x.x.x`, `::1`, `0.0.0.0`, and URLs with an empty host in addition to cloud metadata endpoints

---

[Unreleased]: https://github.com/Failionaire/SpaceJamf/compare/v0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/Failionaire/SpaceJamf/releases/tag/v0.1.0-beta.1
