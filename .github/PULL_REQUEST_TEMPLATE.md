## What does this PR do?

<!-- A concise description of the change and why it's needed. Link the related issue if one exists. -->

Closes #

---

## Type of change

- [ ] Bug fix
- [ ] New feature / collector
- [ ] Scrubber pattern addition
- [ ] Refactor / cleanup
- [ ] Documentation
- [ ] CI / build

---

## Checklist

- [ ] `swift build` passes with no warnings
- [ ] `swift test` passes
- [ ] New collector includes a fixture file and a `CollectorTests.swift` test
- [ ] New scrubber pattern includes a test asserting the sensitive value is **absent** from `scrubbedOutput`
- [ ] `rawOutput` is not passed to `ClaudeClient` or written to any output file
- [ ] No hardcoded secrets, IP addresses, or hostnames in fixtures or tests

---

## Privacy / security notes

<!-- Does this PR change what data is collected, scrubbed, or transmitted? If so, explain what and how it's handled. -->
