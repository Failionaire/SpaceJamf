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
    var outputFormat: String = "terminal"

    @Option(
        name: .long,
        help: "Directory to write the HTML report into (default: current working directory)"
    )
    var outputDir: String = "."

    mutating func run() async throws {
        guard outputFormat == "terminal" || outputFormat == "html" else {
            err("Error: unknown output format '\(outputFormat)'. Valid values: terminal, html")
            throw ExitCode.failure
        }

        guard FileManager.default.fileExists(atPath: jsonPath) else {
            err("Error: file not found: \(jsonPath)")
            throw ExitCode.failure
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        } catch {
            err("Error reading \(jsonPath): \(error)")
            throw ExitCode.failure
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var report: AnalysisReport
        do {
            report = try decoder.decode(AnalysisReport.self, from: data)
        } catch {
            err("Error decoding report: \(error)")
            throw ExitCode.failure
        }

        if report.generatedAt == nil {
            report.generatedAt = Date()
        }

        switch outputFormat {
        case "html":
            let name = "spacejamf-report-\(String(UUID().uuidString.prefix(8)).lowercased()).html"
            let filename = URL(fileURLWithPath: outputDir).appendingPathComponent(name).path
            // Pass empty results — raw output is not stored in the JSON report
            let html = HTMLReporter.render(report: report, results: [:])
            do {
                try html.write(toFile: filename, atomically: true, encoding: .utf8)
                print("Report written to \(URL(fileURLWithPath: filename).absoluteURL.path)")
            } catch {
                err("Failed to write HTML: \(error)")
                throw ExitCode.failure
            }
        default:
            TerminalReporter.render(report: report, results: [:])
        }
    }
}
