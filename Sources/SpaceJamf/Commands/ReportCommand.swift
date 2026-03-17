import ArgumentParser
import Foundation

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Re-render a previously saved JSON diagnostic report (no API call needed)"
    )

    @Argument(help: "Path to the JSON report file saved with `diagnose --save-json`")
    var jsonPath: String

    @Option(
        name: .long,
        help: "Output format: terminal (default) or html"
    )
    var outputFormat: OutputFormat = .terminal

    @Option(
        name: .long,
        help: "Directory to write the HTML report into (default: current working directory)"
    )
    var outputDir: String = "."

    mutating func run() async throws {
        // RC-2: Skip TOCTOU fileExists pre-check; let Data(contentsOf:) report the error directly.
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        } catch {
            err("Error reading \(jsonPath): \(error)")
            throw ExitCode.failure
        }

        let report: AnalysisReport
        do {
            report = try AnalysisReport.decoder.decode(AnalysisReport.self, from: data)
        } catch {
            // R2: Lead with a user-friendly summary; technical detail follows on the next line.
            err("Could not read report file \u2014 the JSON may be from an older version of SpaceJamf.")
            err("  Details: \(error)")
            throw ExitCode.failure
        }
        // RC-1: Do not fabricate a timestamp. generatedAt was stamped in ClaudeClient at
        // analysis time and is persisted in the JSON. If missing, the reporter uses a
        // "Date unavailable" fallback string rather than silently substituting now().

        switch outputFormat {
        case .html:
            let filename = ReportWriter.makeHTMLFilename(in: outputDir)
            // Pass empty results — raw output is not stored in the JSON report.
            let html = HTMLReporter.render(report: report, results: [:])
            do {
                try ReportWriter.writeHTMLReport(html, to: filename, outputDir: outputDir)
            } catch {
                err("\(error)")
                throw ExitCode.failure
            }
        case .terminal:
            TerminalReporter.render(report: report, results: [:])
        }
    }
}
