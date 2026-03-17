import Foundation
#if canImport(Darwin)
import Darwin
#endif
import os

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

// MARK: - Thread-safe flag

/// Thread-safe mutable boolean backed by `OSAllocatedUnfairLock` (lower overhead than NSLock).
private final class AtomicBool: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    init(_ value: Bool) { lock.withLock { $0 = value } }
    var value: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

// MARK: - Shell

/// Thin async wrapper around `Foundation.Process`.
enum Shell {
    // SH1: Suppress SIGPIPE once per process — it is a process-global signal disposition
    // and calling signal() on every Shell.run() invocation is redundant.
    private static let _sigpipeIgnored: Void = { signal(SIGPIPE, SIG_IGN) }()

    /// Run an executable at `path` with `args`, optionally feeding `stdin` data.
    /// Always returns a result — failures are reported via a non-zero exit code
    /// and a descriptive stderr string rather than throwing.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the executable. Never interpreted by a shell.
    ///   - args: Argument vector; each element is passed as-is (no word splitting).
    ///   - timeout: If non-nil, the process is sent SIGTERM after this many seconds
    ///     (followed by SIGKILL after a 5-second grace period) and the result's
    ///     stderr will note the timeout.
    static func run(
        _ path: String,
        args: [String] = [],
        stdin inputData: Data? = nil,
        timeout: TimeInterval? = nil
    ) async -> ShellResult {
        await withCheckedContinuation { continuation in
            // Touch the static to ensure SIGPIPE is suppressed before the first process launch.
            _ = Shell._sigpipeIgnored

            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments     = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            // Assign stdin pipe before run(); write to it *after* run() to avoid
            // deadlock when inputData exceeds the OS pipe buffer (~64 KB on macOS).
            var stdinPipe: Pipe?
            if inputData != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                stdinPipe = pipe
            }

            // SH2: ioQueue serialises appends from both stdout and stderr handlers;
            // removing it would introduce a data race on the output strings.
            let ioQueue = DispatchQueue(label: "com.spacejamf.shell.io")
            var stdoutAccum = Data()
            var stderrAccum = Data()

            // DispatchGroup tracks EOF on both pipes before the continuation is resumed.
            // Continuously draining the pipes via readabilityHandler prevents the child
            // from blocking on write() when its output exceeds the OS pipe buffer —
            // which would cause terminationHandler to never fire (NEW-1).
            let ioGroup = DispatchGroup()
            ioGroup.enter() // stdout EOF
            ioGroup.enter() // stderr EOF

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    ioGroup.leave()
                } else {
                    ioQueue.async { stdoutAccum.append(chunk) }
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    ioGroup.leave()
                } else {
                    ioQueue.async { stderrAccum.append(chunk) }
                }
            }

            // Concurrency-safe flag for timeout state (H-1).
            let timedOut = AtomicBool(false)
            // Capture the unwrapped seconds value now so the timeout message
            // never needs `?? 0` (timedOut is only set when timeout is non-nil) (L-1).
            let timeoutSeconds = Int(timeout ?? 0)
            var timeoutWorkItem: DispatchWorkItem?
            if let t = timeout {
                let workItem = DispatchWorkItem {
                    timedOut.value = true
                    process.terminate()
                    // Follow up with SIGKILL after a grace period in case the child
                    // catches or ignores SIGTERM (e.g. a hung kernel transaction) (NEW-2).
                    // SH3: There is a theoretical PID reuse race between isRunning and kill()
                    // if the child exits and a new process acquires the same PID in the 5 s
                    // window. Eliminating it requires an OS-level process handle (not
                    // available on Darwin without private API). Accepted risk: the window is
                    // narrow and only affects already-timed-out, unresponsive subprocesses.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                timeoutWorkItem = workItem
                DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: workItem)
            }

            process.terminationHandler = { proc in
                timeoutWorkItem?.cancel()
                let exitCode   = proc.terminationStatus
                let didTimeout = timedOut.value
                // Wait for both pipe EOF signals, then read the accumulated data.
                // ioGroup.notify runs on ioQueue (serial), so all append() blocks
                // dispatched by readabilityHandlers are guaranteed to complete first.
                ioGroup.notify(queue: ioQueue) {
                    let stdout = String(data: stdoutAccum, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrAccum, encoding: .utf8) ?? ""
                    let stderrFinal = didTimeout
                        ? "Process timed out after \(timeoutSeconds)s and was terminated."
                        : stderr
                    continuation.resume(
                        returning: ShellResult(
                            stdout:   stdout,
                            stderr:   stderrFinal,
                            exitCode: exitCode
                        )
                    )
                }
            }

            do {
                try process.run()
                // Write stdin after the process has started so the child is already
                // reading — prevents deadlock if inputData exceeds the pipe buffer (M-10).
                if let inputData, let pipe = stdinPipe {
                    DispatchQueue.global().async {
                        pipe.fileHandleForWriting.write(inputData)
                        pipe.fileHandleForWriting.closeFile()
                    }
                }
            } catch {
                timeoutWorkItem?.cancel()
                // Nil out handlers so their EOF callbacks don't fire unexpectedly.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                // Balance the group entries so waiting code doesn't deadlock.
                ioGroup.leave()
                ioGroup.leave()
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

// MARK: - Stderr helper (module-wide utility)

/// Writes `message` + newline to stderr.
/// Intentionally unbuffered — uses write(2) via FileHandle rather than fputs(3)
/// so progress messages appear immediately even when stdout is redirected.
/// Not thread-safe — concurrent calls may interleave output lines.
func err(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
