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
    var outputFormat: String = "terminal"

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

    @Option(
        name: .long,
        help: "Directory to write HTML reports into (default: current working directory)"
    )
    var outputDir: String = "."

    // MARK: - Run

    mutating func run() async throws {
        let selectedAreas = parseAreas()
        guard !selectedAreas.isEmpty else {
            err("No valid areas specified. Valid values: \(DiagnosticArea.allCases.map(\.rawValue).joined(separator: ", "))")
            throw ExitCode.failure
        }

        guard outputFormat == "terminal" || outputFormat == "html" else {
            err("Unknown output format '\(outputFormat)'. Valid values: terminal, html")
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
            if outputFormat == "html" {
                // Produce an HTML report with no AI findings (NEW-10).
                let rawReport = AnalysisReport(
                    findings: [],
                    summary: "Raw diagnostic output only — AI analysis not performed (--no-claude).",
                    generatedAt: Date()
                )
                let filename = htmlFilename()
                let html = HTMLReporter.render(report: rawReport, results: results)
                do {
                    try html.write(toFile: filename, atomically: true, encoding: .utf8)
                    print("Report written to \(URL(fileURLWithPath: filename).absoluteURL.path)")
                } catch {
                    err("Failed to write HTML report: \(error)")
                    throw ExitCode.failure
                }
            } else {
                TerminalReporter.renderRaw(results: results)
            }
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
        // Note: report.generatedAt is set inside ClaudeClient.analyze(); no re-assignment needed.

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
        switch outputFormat {
        case "html":
            let filename = htmlFilename()
            let html = HTMLReporter.render(report: report, results: results)
            do {
                try html.write(toFile: filename, atomically: true, encoding: .utf8)
                print("Report written to \(URL(fileURLWithPath: filename).absoluteURL.path)")
            } catch {
                err("Failed to write HTML report: \(error)")
                throw ExitCode.failure
            }
        default:
            TerminalReporter.render(report: report, results: results)
        }
    }

    // MARK: - Helpers

    func parseAreas() -> [DiagnosticArea] {
        let tokens = areas
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        // Warn about unrecognised tokens (L-8).
        for token in tokens where DiagnosticArea(rawValue: token) == nil {
            err("Warning: unknown area '\(token)' — skipped")
        }
        // Parse, then deduplicate while preserving order (NEW-11).
        var seen = Set<DiagnosticArea>()
        return tokens
            .compactMap { DiagnosticArea(rawValue: $0) }
            .filter { seen.insert($0).inserted }
    }

    private func htmlFilename() -> String {
        let name = "spacejamf-report-\(String(UUID().uuidString.prefix(8)).lowercased()).html"
        return URL(fileURLWithPath: outputDir).appendingPathComponent(name).path
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


