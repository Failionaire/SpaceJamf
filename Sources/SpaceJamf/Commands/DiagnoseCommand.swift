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
    var outputFormat: OutputFormat = .terminal

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
            results[area] = result.withScrubbedOutput(Scrubber.scrub(result.rawOutput))
        }

        // ── Dry run ────────────────────────────────────────────────────────────
        if dryRun {
            printDryRunPayload(results: results)
            return
        }

        // ── No-Claude mode ────────────────────────────────────────────────────
        if noClaude {
            if outputFormat == .html {
                let rawReport = AnalysisReport(
                    findings: [],
                    summary: "Raw diagnostic output only — AI analysis not performed (--no-claude).",
                    generatedAt: Date()
                )
                let filename = ReportWriter.makeHTMLFilename(in: outputDir)
                try writeHTMLOrExit(HTMLReporter.render(report: rawReport, results: results), to: filename, outputDir: outputDir)
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
        // Capture model once so the log message and API call always use the same value.
        let model = Config.model()
        err("Analyzing with Claude \(model)…")
        guard let prompt = await PromptBuilder.build(from: Array(results.values)) else {
            err("No diagnostic results to analyze.")
            throw ExitCode.failure
        }
        var report: AnalysisReport
        do {
            report = try await ClaudeClient.analyze(
                prompt: prompt,
                apiKey: apiKey,
                model:  model
            )
        } catch {
            err("Claude analysis failed: \(error)")
            throw ExitCode.failure
        }

        // ── Optionally persist JSON ───────────────────────────────────────────
        if let savePath = saveJSON {
            do {
                let data = try AnalysisReport.encoder.encode(report)
                try data.write(to: URL(fileURLWithPath: savePath))
                err("Report JSON saved to \(savePath)")
            } catch {
                err("Warning: could not save JSON report: \(error)")
            }
        }

        // ── Render ────────────────────────────────────────────────────────────
        switch outputFormat {
        case .html:
            let filename = ReportWriter.makeHTMLFilename(in: outputDir)
            try writeHTMLOrExit(HTMLReporter.render(report: report, results: results), to: filename, outputDir: outputDir)
        case .terminal:
            TerminalReporter.render(report: report, results: results)
        }
    }

    // RF3: Centralised HTML write helper — prints exactly one error line on failure.
    private func writeHTMLOrExit(_ html: String, to filename: String, outputDir: String) throws {
        do {
            try ReportWriter.writeHTMLReport(html, to: filename, outputDir: outputDir)
        } catch {
            err("\(error)")
            throw ExitCode.failure
        }
    }

    // MARK: - Helpers

    // Internal to allow unit tests to call it directly.
    func parseAreas() -> [DiagnosticArea] {
        let tokens = areas
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        for token in tokens where DiagnosticArea(rawValue: token) == nil {
            err("Warning: unknown area '\(token)' — skipped")
        }
        var seen = Set<DiagnosticArea>()
        return tokens
            .compactMap { DiagnosticArea(rawValue: $0) }
            .filter { seen.insert($0).inserted }
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
        guard geteuid() != 0 else { return }

        err("⚠️  Warning: the following collectors require root for complete output:")
        for collector in needsElevation {
            err("    • \(collector.area.rawValue)")
        }
        err("   Re-run with: sudo spacejamf diagnose\n")
    }

    private func printDryRunPayload(results: [DiagnosticArea: DiagnosticResult]) {
        // Intentionally stdout: dry-run output is the primary deliverable, so it
        // should be pipeable/redirectable independently of progress messages (stderr).
        print("""
        ╔══════════════════════════════════════════╗
        ║  DRY RUN — Scrubbed Claude payload       ║
        ║  No API call has been made.              ║
        ╚══════════════════════════════════════════╝
        """)
        for result in results.values.sorted(by: { $0.area.rawValue < $1.area.rawValue }) {
            print("━━━ \(result.area.displayName) ━━━")
            print(result.scrubbedOutput ?? "")
        }
    }
}

