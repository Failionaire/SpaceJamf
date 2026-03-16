import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    /// Stdout + a labelled stderr block when stderr is non-empty.
    var combined: String {
        var parts: [String] = []
        if !stdout.isEmpty { parts.append(stdout) }
        if !stderr.isEmpty { parts.append("[stderr]: \(stderr)") }
        return parts.joined(separator: "\n")
    }
}

/// Thin async wrapper around `Foundation.Process`.
enum Shell {
    /// Run an executable at `path` with `args`, optionally feeding `stdin` data.
    /// Always returns a result — failures are reported via a non-zero exit code
    /// and a descriptive stderr string rather than throwing.
    ///
    /// - Parameter timeout: If non-nil, the process is sent SIGTERM after this
    ///   many seconds and the result's stderr will note the timeout.
    static func run(
        _ path: String,
        args: [String] = [],
        stdin inputData: Data? = nil,
        timeout: TimeInterval? = nil
    ) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process   = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments     = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            if let inputData {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                stdinPipe.fileHandleForWriting.write(inputData)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            // Schedule a kill if a timeout was requested.
            var timedOut = false
            var timeoutWorkItem: DispatchWorkItem?
            if let timeout {
                let workItem = DispatchWorkItem {
                    timedOut = true
                    process.terminate()
                }
                timeoutWorkItem = workItem
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
            }

            process.terminationHandler = { proc in
                timeoutWorkItem?.cancel()
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderrFinal = timedOut
                    ? "Process timed out after \(Int(timeout ?? 0))s and was terminated."
                    : stderr
                continuation.resume(
                    returning: ShellResult(
                        stdout:   stdout,
                        stderr:   stderrFinal,
                        exitCode: proc.terminationStatus
                    )
                )
            }

            do {
                try process.run()
            } catch {
                timeoutWorkItem?.cancel()
                continuation.resume(
                    returning: ShellResult(
                        stdout:   "",
                        stderr:   "Failed to launch \(path): \(error.localizedDescription)",
                        exitCode: -1
                    )
                )
            }
        }
    }
}

// MARK: - Stderr helper

/// Write `message` + newline to stderr. Available to all commands.
func err(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
