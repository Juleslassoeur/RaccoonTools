import Foundation

/// Manages a dedicated Python virtual environment for RaccoonTools
class PythonEnv {
    static let shared = PythonEnv()

    let venvDir: String
    let pythonPath: String

    private let requiredPackages = [
        "pyobjc-core",
        "pyobjc-framework-Vision",
        "pyobjc-framework-Quartz",
        "pyobjc-framework-Cocoa",
        "Pillow",
    ]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RaccoonTools/venv").path
        self.venvDir = dir
        self.pythonPath = "\(dir)/bin/python3"
    }

    var isReady: Bool {
        FileManager.default.fileExists(atPath: pythonPath)
    }

    /// Setup venv and install packages. Call once at app launch.
    func setup() async {
        if isReady { return }

        print("[RaccoonTools] Setting up Python venv...")

        // Create venv
        let sysPython = "/usr/bin/python3"
        do {
            _ = try await shellExecRaw(sysPython, args: ["-m", "venv", venvDir])
        } catch {
            print("[RaccoonTools] Failed to create venv: \(error)")
            return
        }

        // Install packages
        let pip = "\(venvDir)/bin/pip3"
        do {
            _ = try await shellExecRaw(pip, args: ["install", "--upgrade", "pip"])
            _ = try await shellExecRaw(pip, args: ["install"] + requiredPackages)
            print("[RaccoonTools] Python venv ready")
        } catch {
            print("[RaccoonTools] Failed to install packages: \(error)")
        }
    }

    /// Raw shell exec without the PYTHONPATH injection (used during setup)
    private func shellExecRaw(_ command: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = args

                let pipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let errOutput = String(data: errData, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: "Error: \(errOutput.isEmpty ? output : errOutput)")
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
