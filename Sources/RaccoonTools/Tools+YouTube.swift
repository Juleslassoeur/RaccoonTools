import Foundation

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
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
            return try await shellExec(ytdlp, args: [
                "-x", "--audio-format", "mp3",
                "-o", "\(settings.outputFolder)/%(title)s.%(ext)s", url
            ])
        }
    ))

    // get youtube video
    registry.register(ToolCommand(
        path: ["get", "youtube", "video"],
        description: "Download a YouTube video",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
            return try await shellExec(ytdlp, args: [
                "-o", "\(settings.outputFolder)/%(title)s.%(ext)s", url
            ])
        }
    ))

    // get youtube transcript → .txt
    registry.register(ToolCommand(
        path: ["get", "youtube", "transcript"],
        description: "Download subtitles as .txt from a YouTube video",
        parameterName: "url",
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")
            let output = settings.outputFolder

            // Download subtitles (VTT format)
            let result = try await shellExec(ytdlp, args: [
                "--write-auto-sub", "--sub-lang", "en",
                "--skip-download",
                "-o", "\(output)/%(title)s", url
            ])

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
