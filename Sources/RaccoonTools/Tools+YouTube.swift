import Foundation

// MARK: - yt-dlp progress parsing (pure, unit-testable)

/// Parses a yt-dlp progress line like "[download]  42.3% of 10.5MiB at ..."
/// into a 0–1 fraction. Returns nil for any other line.
@Sendable func parseYtDlpProgress(_ line: String) -> Double? {
    guard line.contains("[download]") else { return nil }
    guard let range = line.range(of: #"\d+(\.\d+)?%"#, options: .regularExpression),
          let pct = Double(line[range].dropLast()) else { return nil }
    return min(max(pct / 100, 0), 1)
}

/// Resolve yt-dlp and make sure a JavaScript runtime is available: YouTube
/// extraction now requires solving JS challenges (nsig / PO tokens), and
/// yt-dlp needs deno (preferred) or node for that. Without one, downloads
/// fail with confusing impersonation/PO-token warnings.
private func ensureYtDlp() async throws -> (path: String, commonArgs: [String]) {
    let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
    _ = try? await ensureDep("deno", brew: "deno")
    // Allow node as a fallback runtime (only deno is enabled by default)
    return (ytdlp, ["--js-runtimes", "deno", "--js-runtimes", "node"])
}

func registerYouTubeTools(registry: ToolRegistry, settings: SettingsManager) {
    // ============================================================
    // MARK: - GET tools
    // ============================================================

    // get youtube sound
    registry.register(ToolCommand(
        path: ["get", "youtube", "sound"],
        description: "Download audio from a YouTube video (MP3)",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let (ytdlp, commonArgs) = try await ensureYtDlp()
            let taskID = await runningTaskID(for: "get youtube sound")
            return try await shellExec(ytdlp, args: commonArgs + [
                "-x", "--audio-format", "mp3",
                "-o", "\(settings.outputFolder)/%(title)s.%(ext)s", url
            ], taskID: taskID, onLine: progressLineHandler(taskID: taskID, parser: parseYtDlpProgress))
        }
    ))

    // get youtube video
    registry.register(ToolCommand(
        path: ["get", "youtube", "video"],
        description: "Download a YouTube video",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let (ytdlp, commonArgs) = try await ensureYtDlp()
            let taskID = await runningTaskID(for: "get youtube video")
            return try await shellExec(ytdlp, args: commonArgs + [
                "-o", "\(settings.outputFolder)/%(title)s.%(ext)s", url
            ], taskID: taskID, onLine: progressLineHandler(taskID: taskID, parser: parseYtDlpProgress))
        }
    ))

    // get youtube transcript → .txt
    registry.register(ToolCommand(
        path: ["get", "youtube", "transcript"],
        description: "Download subtitles as .txt from a YouTube video",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let (ytdlp, commonArgs) = try await ensureYtDlp()
            let output = settings.outputFolder
            let taskID = await runningTaskID(for: "get youtube transcript")

            // Download subtitles (VTT format). Manual subs are preferred over
            // auto-generated ones; accept English, French and the configured
            // translate target so non-English videos work too.
            var subLangs = ["en", "fr"]
            let target = settings.defaultTranslateTarget
            if !target.isEmpty && !subLangs.contains(target) { subLangs.append(target) }
            let result = try await shellExec(ytdlp, args: commonArgs + [
                "--write-sub", "--write-auto-sub",
                "--sub-lang", subLangs.joined(separator: ","),
                "--skip-download",
                "-o", "\(output)/%(title)s", url
            ], taskID: taskID, onLine: progressLineHandler(taskID: taskID, parser: parseYtDlpProgress))

            // Convert VTT files to plain .txt
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(atPath: output) {
                for file in files where file.hasSuffix(".vtt") {
                    let vttPath = "\(output)/\(file)"
                    if let content = try? String(contentsOfFile: vttPath, encoding: .utf8) {
                        let txt = vttToPlainText(content)
                        let txtPath = vttPath.replacingOccurrences(of: ".vtt", with: ".txt")
                        try? txt.write(toFile: txtPath, atomically: true, encoding: .utf8)
                        try? fm.removeItem(atPath: vttPath)
                    }
                }
            }

            return result.contains("Error") ? result : "Transcript saved as .txt to \(output)"
        }
    ))
}

// MARK: - VTT to plain text converter

func vttToPlainText(_ vtt: String) -> String {
    var lines: [String] = []
    var lastLine = ""
    for line in vtt.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Skip VTT headers, timestamps, and empty lines
        if trimmed.isEmpty || trimmed.hasPrefix("WEBVTT") || trimmed.hasPrefix("Kind:")
            || trimmed.hasPrefix("Language:") || trimmed.contains("-->")
            || trimmed.allSatisfy({ $0.isNumber || $0 == ":" || $0 == "." || $0 == " " }) {
            continue
        }
        // Remove HTML tags from subtitle text
        let clean = trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if clean != lastLine && !clean.isEmpty {
            lines.append(clean)
            lastLine = clean
        }
    }
    return lines.joined(separator: "\n")
}
