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

    var errorDescription: String? {
        switch self {
        case .dependencyMissing(let name):
            return "\(name) not found. Run: brew install \(name)"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Shell execution

func shellExec(_ command: String, args: [String], taskID: UUID? = nil) async throws -> String {
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
                try process.run()
                process.waitUntilExit()
                if let taskID { ProcessManager.shared.processes.removeValue(forKey: taskID) }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errOutput = String(data: errData, encoding: .utf8) ?? ""

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
