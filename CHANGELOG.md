# Changelog

All notable changes to SpaceJamf will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- Initial project structure and architecture
- `CollectorProtocol` with `requiresElevation` pre-flight checking
- `ADCollector` — Active Directory binding diagnostics via `dsconfigad`, `klist`, `dscl`
- `JamfCollector` — JSS connectivity and MDM profile checks
- `CertCollector` — certificate validity and chain checks
- `NetworkCollector` — DNS resolution and JSS reachability
- `ClockCollector` — NTP sync and clock skew detection
- `Scrubber` — regex-based redaction of IPs, Kerberos tickets, and credentials
- `ClaudeClient` — async Anthropic API integration via `URLSession`
- `PromptBuilder` — structured prompt assembly with OS context
- `TerminalReporter` — ANSI severity badges and confidence indicators
- `HTMLReporter` — self-contained single-file HTML report
- `--no-claude` flag for offline/API-key-free usage
- `--dry-run` flag to inspect scrubbed payload without making API calls
- `--areas` flag to limit collection to specific diagnostic areas
- `--output html` flag to generate a shareable HTML report
- `spacejamf report` subcommand to re-render saved JSON reports

---

[Unreleased]: https://github.com/Failionaire/SpaceJamf/compare/HEAD...HEAD
