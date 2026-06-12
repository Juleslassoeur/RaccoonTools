import Foundation

// MARK: - Dependency management

func ensureDep(_ name: String, brew: String? = nil) async throws -> String {
    let paths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)",
    ]
    for path in paths {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    if let result = try? await shellExec("/bin/zsh", args: ["-lc", "which \(name)"]) {
        let found = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !found.isEmpty && found.contains("/") && !found.contains("not found") {
            return found
        }
    }
    if let brew {
        let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
        if FileManager.default.fileExists(atPath: brewPath) {
            _ = try await shellExec(brewPath, args: ["install", brew])
            for path in paths {
                if FileManager.default.fileExists(atPath: path) { return path }
            }
        }
    }
    throw ToolError.dependencyMissing(name)
}

enum ToolError: LocalizedError {
    case dependencyMissing(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .dependencyMissing(let name):
            return "\(name) not found. Run: brew install \(name)"
        case .cancelled:
            return "Cancelled"
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Line splitting (pure, unit-testable)

/// Splits a stream buffer into complete lines plus a trailing partial line.
/// Both \n and \r terminate a line (yt-dlp redraws progress with \r).
func splitStreamLines(_ buffer: String) -> (lines: [String], remainder: String) {
    var lines: [String] = []
    var current = String.UnicodeScalarView()
    // Iterate scalars, not Characters: "\r\n" is a single grapheme cluster
    // and would otherwise slip through the separator check
    for scalar in buffer.unicodeScalars {
        if scalar == "\n" || scalar == "\r" {
            lines.append(String(current))
            current = String.UnicodeScalarView()
        } else {
            current.append(scalar)
        }
    }
    return (lines, String(current))
}

/// Accumulates a pipe's output while forwarding complete, non-empty lines
/// to an optional callback. Thread-safe: readabilityHandler fires on a
/// background queue.
private final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var pending = ""
    private let onLine: (@Sendable (String) -> Void)?
    private let done = DispatchSemaphore(value: 0)

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func attach(to handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fh in
            let chunk = fh.availableData
            guard let self else { return }
            if chunk.isEmpty {
                fh.readabilityHandler = nil
                self.finish()
            } else {
                self.ingest(chunk)
            }
        }
    }

    private func ingest(_ chunk: Data) {
        var emit: [String] = []
        lock.lock()
        data.append(chunk)
        if let str = String(data: chunk, encoding: .utf8) {
            let (lines, remainder) = splitStreamLines(pending + str)
            pending = remainder
            emit = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        lock.unlock()
        if let onLine { emit.forEach(onLine) }
    }

    private func finish() {
        var last: String?
        lock.lock()
        if !pending.trimmingCharacters(in: .whitespaces).isEmpty { last = pending }
        pending = ""
        lock.unlock()
        if let onLine, let last { onLine(last) }
        done.signal()
    }

    /// Wait for EOF so the accumulated output is complete (with a safety timeout).
    func waitUntilDrained(timeout: TimeInterval = 5) {
        _ = done.wait(timeout: .now() + timeout)
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Shell execution

/// Runs a process and returns its output. When `onLine` is provided, each
/// complete non-empty stdout/stderr line is forwarded as it arrives
/// (split on both \n and \r) — used for live progress reporting.
func shellExec(_ command: String, args: [String], taskID: UUID? = nil,
               onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
            if let taskID { ProcessManager.shared.register(taskID, process: process) }

            // Ensure brew + venv are in PATH
            var env = ProcessInfo.processInfo.environment
            let brewPaths = "/opt/homebrew/bin:/usr/local/bin"
            let venvBin = PythonEnv.shared.venvDir + "/bin"
            env["PATH"] = "\(venvBin):\(brewPaths):\(env["PATH"] ?? "/usr/bin:/bin")"
            process.environment = env

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            do {
                let output: String
                let errOutput: String

                if let onLine {
                    // Streaming mode: accumulate via readabilityHandler so we
                    // can forward lines live while keeping the full output.
                    let outCollector = PipeCollector(onLine: onLine)
                    let errCollector = PipeCollector(onLine: onLine)
                    outCollector.attach(to: pipe.fileHandleForReading)
                    errCollector.attach(to: errPipe.fileHandleForReading)

                    try process.run()
                    process.waitUntilExit()
                    outCollector.waitUntilDrained()
                    errCollector.waitUntilDrained()

                    output = outCollector.output
                    errOutput = errCollector.output
                } else {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    output = String(data: data, encoding: .utf8) ?? ""
                    errOutput = String(data: errData, encoding: .utf8) ?? ""
                }

                if let taskID { ProcessManager.shared.processes.removeValue(forKey: taskID) }

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output.isEmpty ? "Done" : output)
                } else if process.terminationStatus == 15 {
                    continuation.resume(throwing: ToolError.cancelled)
                } else {
                    let msg = errOutput.isEmpty ? output : errOutput
                    continuation.resume(returning: "Error (exit \(process.terminationStatus)): \(msg)")
                }
            } catch {
                if let taskID { ProcessManager.shared.processes.removeValue(forKey: taskID) }
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Task progress helpers

/// Looks up the running-task ID for a tool. The UI registers the task
/// (SpotlightState.addRunningTask) right before invoking the handler, so
/// the most recent entry for this tool path is the current execution.
@MainActor
func runningTaskID(for toolPath: String) -> UUID? {
    SpotlightState.shared.runningTasks.last(where: { $0.toolName == toolPath })?.id
}

/// Builds a shellExec `onLine` callback that parses progress from output
/// lines and updates the task's progress bar on the main thread.
/// Returns nil when there is no task to report to.
func progressLineHandler(taskID: UUID?,
                         parser: @escaping @Sendable (String) -> Double?) -> (@Sendable (String) -> Void)? {
    guard let taskID else { return nil }
    return { line in
        guard let progress = parser(line) else { return }
        Task { @MainActor in
            SpotlightState.shared.updateTaskProgress(taskID, progress)
        }
    }
}
