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

// MARK: - YouTube video id extraction (pure, unit-testable)

func youtubeVideoID(from url: String) -> String? {
    if let range = url.range(of: #"(?:v=|youtu\.be/|shorts/|embed/|live/)([A-Za-z0-9_-]{11})"#,
                             options: .regularExpression) {
        return String(url[range].suffix(11))
    }
    if url.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
        return url
    }
    return nil
}

/// Transcript fetch via youtube-transcript-api (runs in the app's venv):
/// talks to the timedtext endpoint directly, ~2s instead of a full yt-dlp
/// extraction. Track choice mirrors chooseSubtitleTrack: manual in a
/// preferred language > any manual > the original auto-generated track.
private let transcriptPythonScript = """
import sys
from youtube_transcript_api import YouTubeTranscriptApi

video_id, prefs = sys.argv[1], [p for p in sys.argv[2].split(',') if p]
tracks = list(YouTubeTranscriptApi().list(video_id))

def match(ts, lang):
    for t in ts:
        if t.language_code == lang or t.language_code.startswith(lang + '-'):
            return t

manual = [t for t in tracks if not t.is_generated]
generated = [t for t in tracks if t.is_generated]
choice = None
for p in prefs:
    choice = match(manual, p)
    if choice: break
if not choice and manual: choice = manual[0]
if not choice:
    for p in prefs:
        choice = match(generated, p)
        if choice: break
if not choice and generated: choice = generated[0]
if not choice:
    print('NO_TRANSCRIPT'); sys.exit(0)

data = choice.fetch()
snippets = data.snippets if hasattr(data, 'snippets') else data
print('LANG:%s:%s' % (choice.language_code, 'auto-generated' if choice.is_generated else 'manual'))
for s in snippets:
    text = s.text if hasattr(s, 'text') else s['text']
    if text and text.strip():
        print(text.strip().replace('\\n', ' '))
"""

// MARK: - Subtitle track selection (pure, unit-testable)

struct SubtitleTrackChoice: Equatable {
    let lang: String
    let isAutomatic: Bool
}

/// Pick the best subtitle track from a yt-dlp `-J` info dump, instead of
/// blindly requesting fixed languages: requesting a language that doesn't
/// exist hits YouTube's on-the-fly translation endpoint, which is heavily
/// rate-limited (HTTP 429).
///
/// Order: manual subs in a preferred language → any manual subs → the
/// ORIGINAL auto-generated track ("xx-orig", served directly, not throttled)
/// → auto track matching the video language → auto in a preferred language
/// → any auto track.
func chooseSubtitleTrack(infoJSON: String, preferred: [String]) -> SubtitleTrackChoice? {
    // yt-dlp's -J dump can contain raw control characters inside string
    // values, which strict JSON parsers reject — strip them (the dump is a
    // single line, so no meaningful whitespace is lost).
    let sanitized = String(String.UnicodeScalarView(infoJSON.unicodeScalars.filter { $0.value >= 0x20 }))
    guard let start = sanitized.firstIndex(of: "{"),
          let data = String(sanitized[start...]).data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let manual = (json["subtitles"] as? [String: Any]) ?? [:]
    let auto = (json["automatic_captions"] as? [String: Any]) ?? [:]
    let prefs = preferred.filter { !$0.isEmpty }

    func match(_ keys: some Collection<String>, _ lang: String) -> String? {
        keys.first { $0 == lang || $0.hasPrefix(lang + "-") }
    }

    for p in prefs {
        if let lang = match(manual.keys, p) { return SubtitleTrackChoice(lang: lang, isAutomatic: false) }
    }
    if let lang = manual.keys.sorted().first { return SubtitleTrackChoice(lang: lang, isAutomatic: false) }

    if let orig = auto.keys.first(where: { $0.hasSuffix("-orig") }) {
        return SubtitleTrackChoice(lang: orig, isAutomatic: true)
    }
    if let videoLang = json["language"] as? String, let lang = match(auto.keys, videoLang) {
        return SubtitleTrackChoice(lang: lang, isAutomatic: true)
    }
    for p in prefs {
        if let lang = match(auto.keys, p) { return SubtitleTrackChoice(lang: lang, isAutomatic: true) }
    }
    if let lang = auto.keys.sorted().first { return SubtitleTrackChoice(lang: lang, isAutomatic: true) }
    return nil
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
            let output = settings.outputFolder
            let prefs = [settings.defaultTranslateTarget, "fr", "en"].filter { !$0.isEmpty }

            // Fast path (~2s): fetch the transcript directly via
            // youtube-transcript-api instead of a full yt-dlp extraction.
            if let videoID = youtubeVideoID(from: url), PythonEnv.shared.isReady {
                do {
                    let raw = try await shellExec(PythonEnv.shared.pythonPath, args: [
                        "-W", "ignore", "-c", transcriptPythonScript,
                        videoID, prefs.joined(separator: ",")
                    ])
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("NO_TRANSCRIPT") {
                        return "No subtitles available for this video (neither manual nor auto-generated)."
                    }
                    var lines = trimmed.components(separatedBy: "\n")
                    var trackDesc = "transcript"
                    if let first = lines.first, first.hasPrefix("LANG:") {
                        let parts = first.split(separator: ":")
                        if parts.count >= 3 { trackDesc = "\(parts[1]), \(parts[2])" }
                        lines.removeFirst()
                    }
                    let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let path = "\(output)/youtube-transcript-\(videoID).txt"
                        try text.write(toFile: path, atomically: true, encoding: .utf8)
                        return "Transcript (\(trackDesc)) saved to \(path)"
                    }
                } catch {
                    // Fall through to the yt-dlp path below
                }
            }

            // Fallback: yt-dlp two-step (list tracks, then download the best)
            let (ytdlp, commonArgs) = try await ensureYtDlp()
            let taskID = await runningTaskID(for: "get youtube transcript")

            // 1) Ask what subtitle tracks actually exist (one request) and
            // pick the best one — requesting a missing language triggers
            // YouTube's rate-limited translation endpoint (HTTP 429).
            let infoJSON = try await shellExec(ytdlp, args: commonArgs + ["-J", url], taskID: taskID)
            guard let choice = chooseSubtitleTrack(
                infoJSON: infoJSON,
                preferred: [settings.defaultTranslateTarget, "fr", "en"]
            ) else {
                return "No subtitles available for this video (neither manual nor auto-generated)."
            }

            // 2) Download exactly that track
            let result = try await shellExec(ytdlp, args: commonArgs + [
                choice.isAutomatic ? "--write-auto-sub" : "--write-sub",
                "--sub-lang", choice.lang,
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

            let trackDesc = choice.isAutomatic ? "\(choice.lang), auto-generated" : choice.lang
            return result.contains("Error") ? result : "Transcript (\(trackDesc)) saved as .txt to \(output)"
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
