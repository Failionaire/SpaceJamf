import ArgumentParser
import Foundation

/// Namespace for HTML report filename generation and writing (RF2).
enum ReportWriter {

    // RF1: Allocate the formatter once — ISO8601DateFormatter is expensive to initialise.
    private static let filenameFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatingHoursAndMinutes]
        return f
    }()

    /// Generates a timestamped HTML report filename inside the given directory.
    static func makeHTMLFilename(in outputDir: String) -> String {
        let stamp = filenameFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let name = "spacejamf-report-\(stamp).html"
        return URL(fileURLWithPath: outputDir).appendingPathComponent(name).path
    }

    /// Writes an HTML string to `filename`, validating that `outputDir` exists first.
    /// Prints the output path to stdout on success.
    /// RF3: Throws a typed `WriteError` rather than calling `err()` internally so
    /// the caller prints exactly one error message (avoiding double output).
    static func writeHTMLReport(_ html: String, to filename: String, outputDir: String) throws {
        let dirURL = URL(fileURLWithPath: outputDir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw WriteError.directoryNotFound(dirURL.path)
        }
        do {
            try html.write(toFile: filename, atomically: true, encoding: .utf8)
            print("Report written to \(URL(fileURLWithPath: filename).absoluteURL.path)")
        } catch {
            throw WriteError.writeFailed(error)
        }
    }

    // RF3: Typed errors let the caller print exactly one message.
    enum WriteError: Error, CustomStringConvertible {
        case directoryNotFound(String)
        case writeFailed(Error)

        var description: String {
            switch self {
            case .directoryNotFound(let path):
                return "Output directory does not exist: \(path)"
            case .writeFailed(let underlying):
                return "Failed to write HTML report: \(underlying)"
            }
        }
    }
}
