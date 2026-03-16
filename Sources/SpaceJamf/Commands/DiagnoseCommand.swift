import ArgumentParser
import Foundation

struct DiagnoseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose",
        abstract: "Run macOS diagnostics and analyze findings with Claude AI"
    )

    // MARK: - Options

    @Option(
        name: .long,
        help: "Comma-separated list of areas to collect: ad,jamf,certs,network,clock (default: all)"
    )
    var areas: String = DiagnosticArea.allCases.map(\.rawValue).joined(separator: ",")

    @Option(
        name: .long,
        help: "Output format: terminal (default) or html"
    )
    var output: String = "terminal"

    @Flag(
        name: .long,
        help: "Display scrubbed diagnostic output only — skip Claude AI analysis"
    )
    var noClaude: Bool = false

    @Flag(
        name: .long,
        help: "Print the exact scrubbed payload that would be sent to Claude, then exit — no API call made"
    )
    var dryRun: Bool = false

    @Option(
        name: .long,
        help: "Save the analysis report as JSON at this path (for later re-rendering with `report`)"
    )
    var saveJSON: String?

    // MARK: - Run

    mutating func run() async throws {
        let selectedAreas = parseAreas()
        guard !selectedAreas.isEmpty else {
            err("No valid areas specified. Valid values: \(DiagnosticArea.allCases.map(\.rawValue).joined(separator: ", "))")
            throw ExitCode.failure
        }

        guard output == "terminal" || output == "html" else {
            err("Unknown output format '\(output)'. Valid values: terminal, html")
            throw ExitCode.failure
        }

        let collectors = buildCollectors(for: selectedAreas)
        preflightElevationCheck(collectors: collectors)

        // ── Concurrent collection ─────────────────────────────────────────────
        err("Collecting diagnostics…")
        var rawResults: [DiagnosticArea: DiagnosticResult] = [:]

        await withTaskGroup(of: (DiagnosticArea, DiagnosticResult).self) { group in
            for collector in collectors {
                group.addTask { (collector.area, await collector.collect()) }
            }
            for await (area, result) in group {
                rawResults[area] = result
            }
        }

        // ── Scrub ──────────────────────────────────────────────────────────────
        var results: [DiagnosticArea: DiagnosticResult] = [:]
        for (area, result) in rawResults {
            var scrubbed = result
            scrubbed.scrubbedOutput = Scrubber.scrub(result.rawOutput)
            results[area] = scrubbed
        }

        // ── Dry run ────────────────────────────────────────────────────────────
        if dryRun {
            printDryRunPayload(results: results)
            return
        }

        // ── No-Claude mode ────────────────────────────────────────────────────
        if noClaude {
            TerminalReporter.renderRaw(results: results)
            return
        }

        // ── Resolve API key ───────────────────────────────────────────────────
        let apiKey: String
        do {
            apiKey = try Config.anthropicAPIKey()
        } catch {
            err("\(error)")
            throw ExitCode.failure
        }

        // ── Build prompt + call Claude ────────────────────────────────────────
        err("Analyzing with Claude \(Config.model())…")
        let prompt = await PromptBuilder.build(from: Array(results.values))
        var report: AnalysisReport
        do {
            report = try await ClaudeClient.analyze(
                prompt: prompt,
                apiKey: apiKey,
                model:  Config.model()
            )
        } catch {
            err("Claude analysis failed: \(error)")
            throw ExitCode.failure
        }
        report.generatedAt = Date()

        // ── Optionally persist JSON ───────────────────────────────────────────
        if let savePath = saveJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting    = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(report)
                try data.write(to: URL(fileURLWithPath: savePath))
                err("Report JSON saved to \(savePath)")
            } catch {
                err("Warning: could not save JSON report: \(error)")
            }
        }

        // ── Render ────────────────────────────────────────────────────────────
        switch output {
        case "html":
            let filename = "spacejamf-report-\(String(UUID().uuidString.prefix(8)).lowercased()).html"
            let html = HTMLReporter.render(report: report, results: results)
            do {
                try html.write(toFile: filename, atomically: true, encoding: .utf8)
                print("HTML report saved to \(filename)")
            } catch {
                err("Failed to write HTML report: \(error)")
                throw ExitCode.failure
            }
        default:
            TerminalReporter.render(report: report, results: results)
        }
    }

    // MARK: - Helpers

    private func parseAreas() -> [DiagnosticArea] {
        areas
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .compactMap { DiagnosticArea(rawValue: $0) }
    }

    private func buildCollectors(
        for areas: [DiagnosticArea]
    ) -> [any CollectorProtocol] {
        areas.map { area in
            switch area {
            case .ad:      return ADCollector()      as any CollectorProtocol
            case .jamf:    return JamfCollector()    as any CollectorProtocol
            case .certs:   return CertCollector()    as any CollectorProtocol
            case .network: return NetworkCollector() as any CollectorProtocol
            case .clock:   return ClockCollector()   as any CollectorProtocol
            }
        }
    }

    private func preflightElevationCheck(
        collectors: [any CollectorProtocol]
    ) {
        let needsElevation = collectors.filter { $0.requiresElevation }
        guard !needsElevation.isEmpty else { return }

        // geteuid() == 0 means running as root / via sudo
        guard geteuid() != 0 else { return }

        err("⚠️  Warning: the following collectors require root for complete output:")
        for collector in needsElevation {
            err("    • \(collector.area.rawValue)")
        }
        err("   Re-run with: sudo spacejamf diagnose\n")
    }

    private func printDryRunPayload(results: [DiagnosticArea: DiagnosticResult]) {
        print("""
        ╔══════════════════════════════════════════╗
        ║  DRY RUN — Scrubbed Claude payload       ║
        ║  No API call has been made.              ║
        ╚══════════════════════════════════════════╝
        """)
        for result in results.values.sorted(by: { $0.area.rawValue < $1.area.rawValue }) {
            print("━━━ \(result.area.rawValue.uppercased()) ━━━")
            print(result.scrubbedOutput ?? "")
        }
    }
}


