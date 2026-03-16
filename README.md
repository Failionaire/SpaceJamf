# COME ON AND SLAM, AND WELCOME TO SPACEJAMF!

This is a native Swift CLI tool that diagnoses broken or messed up Jamf MDM ↔ Active Directory bindings on macOS, and uses Claude AI to explain root causes and suggest fixes in plain English.

I wrote the original non-AI version of this for myself years ago, but I decided to create a modern version that incorporates AI to help analyze and explain things in human language.

> **Privacy first:** Raw diagnostic output **never leaves your device.** Only scrubbed, redacted output is sent to the Claude API. See [Privacy](#privacy) for details.

---

## Why SpaceJamf?

Enterprise macOS admins hit the same painful wall constantly: AD bindings break, Kerberos tickets expire, JSS connectivity silently degrades, and certificates quietly die. Diagnosing it means running a dozen commands, parsing noisy output, and cross-referencing four different knowledge bases.

SpaceJamf runs all of that for you, redacts sensitive data, and asks Claude to explain *why* things broke and *exactly* how to fix them. All sorted by severity, with a confidence indicator so you know when it's certain vs. inferring.

```
$ sudo spacejamf diagnose

⠸ Collecting diagnostics...

[CRITICAL] (certain)   Kerberos ticket cache is empty or expired
  Root cause: The machine's TGT expired and was not renewed, likely due to
              the user not logging in for >10 hours on a disconnected network.
  Fix:
    1. Run: kinit -k -t /etc/krb5.keytab host/$(hostname)
    2. Verify with: klist -v
    3. If the keytab is missing, re-bind to AD: dsconfigad -add ...

[WARNING]  (inferred)  JSS connection degraded — HTTP 200 but slow response (4.2s)
  Root cause: DNS resolution for your JSS URL is returning a non-CDN IP.
              This suggests a split-DNS misconfiguration.
  Fix:
    1. Confirm JSS URL resolves correctly: host jss.example.com
    2. Check /etc/resolv.conf points to internal DNS servers
    ...

[INFO]     (certain)   NTP is synced — clock skew is 0.3s (well within Kerberos tolerance)
```

---

## What It Checks

| Area | Commands Used | Requires `sudo` |
|---|---|---|
| **Active Directory** | `dsconfigad -show`, `klist -v`, `dscl` | Yes |
| **Jamf JSS** | `jamf checkJSSConnection`, `jamf version`, `profiles list/show` | No |
| **Certificates** | `security find-certificate`, `openssl x509` | No |
| **Network / DNS** | `host`, `curl` reachability checks | No |
| **Clock / NTP** | `sntp`, `systemsetup -getusingnetworktime` | No |

SpaceJamf warns you upfront which collectors need elevation before running anything, no silent mid-collection failures.

Works fine on Macs not enrolled in Jamf: `JamfCollector` gracefully reports the binary as missing rather than crashing.

---

## Installation

### Homebrew (recommended)

```bash
brew tap Failionaire/spacejamf
brew install spacejamf
```

### GitHub Releases (universal binary)

Download the latest pre-built universal binary (`arm64` + `x86_64`) from the [Releases page](../../releases/latest):

```bash
curl -L https://github.com/Failionaire/SpaceJamf/releases/latest/download/spacejamf.zip -o spacejamf.zip
unzip spacejamf.zip
sudo mv spacejamf /usr/local/bin/
```

### Build from source

Requires Swift 5.7+ (ships with Xcode 14+) and macOS 13+.

```bash
git clone https://github.com/Failionaire/SpaceJamf.git
cd SpaceJamf
swift build -c release
sudo cp .build/release/spacejamf /usr/local/bin/
```

---

## Requirements

- macOS 13 Ventura or later (Man, time sure flies)
- Swift 5.7+ / Xcode 14+ (build from source only)
- An [Anthropic API key](https://console.anthropic.com/) — optional; use `--no-claude` to skip AI analysis

---

## Configuration

SpaceJamf looks for your Anthropic API key in this order:

1. `ANTHROPIC_API_KEY` environment variable
2. `~/.spacejamf/config` (plain text, see below)

```bash
# Create config directory
mkdir -p ~/.spacejamf

# Write your API key
echo "ANTHROPIC_API_KEY=sk-ant-..." > ~/.spacejamf/config

# Restrict permissions
chmod 600 ~/.spacejamf/config
```

You can also override the default Claude model in the config:

```
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_MODEL=claude-sonnet-4-6
```

---

## Usage

### Full diagnosis (recommended: run with sudo)

```bash
sudo spacejamf diagnose
```

### Limit to specific areas

```bash
sudo spacejamf diagnose --areas ad,jamf
sudo spacejamf diagnose --areas certs,network,clock
```

Available areas: `ad`, `jamf`, `certs`, `network`, `clock`

### Generate an HTML report

```bash
sudo spacejamf diagnose --output html
# Writes: spacejamf-report-2026-03-16T14-32-00.html
```

### Run without Claude (no API key needed)

Displays raw scrubbed diagnostic output in the terminal. This is useful for quick triage or when offline.

```bash
sudo spacejamf diagnose --no-claude
```

### Dry run — inspect what would be sent to Claude

Prints the exact scrubbed payload that *would* be sent to the API, then exits without making any network calls. Use this to verify redaction before trusting the tool in a sensitive environment.

```bash
sudo spacejamf diagnose --dry-run
```

### Re-render a saved report

```bash
spacejamf report spacejamf-report-2026-03-16T14-32-00.json
spacejamf report spacejamf-report-2026-03-16T14-32-00.json --output html
```

### All flags

```
USAGE: spacejamf diagnose [--areas <areas>] [--output <format>] [--no-claude] [--dry-run]

OPTIONS:
  --areas <areas>     Comma-separated list of diagnostic areas to run.
                      Options: ad, jamf, certs, network, clock
                      Default: all areas
  --output <format>   Output format: terminal (default) or html
  --no-claude         Skip Claude analysis; display raw scrubbed output only
  --dry-run           Print the scrubbed Claude payload to stdout and exit
                      without making any API calls
  -h, --help          Show help information
```

---

## Privacy

SpaceJamf is designed for use in environments where diagnostic data is sensitive.

**What stays on your device:**
- All raw command output (`rawOutput`). This is kept locally only and is never transmitted
- Your API key

**What is sent to the Claude API (only when not using `--no-claude` or `--dry-run`):**
- Scrubbed output with the following redacted:
  - IPv4 and IPv6 addresses → `[IP_REDACTED]`
  - Kerberos ticket blobs → `[TICKET_REDACTED]`
  - Any line containing `password:` → `[CREDENTIAL_REDACTED]`
- macOS version (`sw_vers`) and architecture (`uname -m`)

Use `--dry-run` to inspect the exact payload before it is ever sent.

Anthropic's [privacy policy](https://www.anthropic.com/privacy) and [usage policy](https://www.anthropic.com/legal/aup) apply to data sent via the API.

---

## How It Works

```
spacejamf diagnose
       │
       ▼
Pre-flight: warn which collectors need elevation (before running anything)
       │
       ▼
Run collectors concurrently (TaskGroup)
  ADCollector · JamfCollector · CertCollector · NetworkCollector · ClockCollector
       │
       ▼
Scrubber: redact IPs, tickets, credentials → scrubbedOutput
       │
       ├── [--dry-run]  → print payload, exit
       │
       ▼
PromptBuilder: structure scrubbed output + OS context into Claude prompt
       │
       ▼
ClaudeClient: POST /v1/messages → [Finding] sorted by severity
       │
       ├── TerminalReporter → ANSI output to stdout
       └── HTMLReporter     → self-contained .html file
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

MIT — see [LICENSE](LICENSE).
