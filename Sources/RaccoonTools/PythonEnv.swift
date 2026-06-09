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
        "youtube-transcript-api",
    ]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RaccoonTools/venv").path
        self.venvDir = dir
        self.pythonPath = "\(dir)/bin/python3"
    }

    /// Written only after a fully successful install; its absence means the
    /// venv is incomplete and must be rebuilt.
    private var markerPath: String { "\(venvDir)/.raccoon_setup_ok" }

    var isReady: Bool {
        guard FileManager.default.fileExists(atPath: pythonPath),
              let marker = try? String(contentsOfFile: markerPath, encoding: .utf8) else { return false }
        // The marker records what was installed; a mismatch (e.g. a new
        // required package) triggers a clean rebuild on next launch
        return marker == requiredPackages.joined(separator: "\n")
    }

    /// Setup venv and install packages. Call once at app launch.
    func setup() async {
        if isReady { return }

        let fm = FileManager.default
        let sysPython = "/usr/bin/python3"
        guard fm.fileExists(atPath: sysPython) else {
            print("[RaccoonTools] /usr/bin/python3 not found — install the Command Line Tools (`xcode-select --install`) to enable PDF/OCR tools")
            return
        }

        // A venv without the marker is a leftover from a failed install
        if fm.fileExists(atPath: venvDir) {
            try? fm.removeItem(atPath: venvDir)
        }

        print("[RaccoonTools] Setting up Python venv...")

        do {
            _ = try await shellExecRaw(sysPython, args: ["-m", "venv", venvDir])
            let pip = "\(venvDir)/bin/pip3"
            _ = try await shellExecRaw(pip, args: ["install", "--upgrade", "pip"])
            _ = try await shellExecRaw(pip, args: ["install"] + requiredPackages)
            try requiredPackages.joined(separator: "\n")
                .write(toFile: markerPath, atomically: true, encoding: .utf8)
            print("[RaccoonTools] Python venv ready")
        } catch {
            print("[RaccoonTools] Python venv setup failed: \(error.localizedDescription) — removing venv, will retry on next launch")
            try? fm.removeItem(atPath: venvDir)
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
                        let message = errOutput.isEmpty ? output : errOutput
                        continuation.resume(throwing: NSError(
                            domain: "PythonEnv",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
