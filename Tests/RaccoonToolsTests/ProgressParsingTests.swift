import Testing
@testable import RaccoonTools

@Suite struct ProgressParsingTests {

    // MARK: - yt-dlp

    @Test func ytDlpDownloadLineParsesPercent() {
        let pct = parseYtDlpProgress("[download]  42.3% of 10.55MiB at 2.31MiB/s ETA 00:02")
        #expect(pct != nil && abs(pct! - 0.423) < 1e-9)
        #expect(parseYtDlpProgress("[download]   0.0% of ~3.46MiB at Unknown B/s ETA Unknown") == 0.0)
        #expect(parseYtDlpProgress("[download] 100% of 10.55MiB in 00:04") == 1.0)
        #expect(parseYtDlpProgress("[download]   5% of 1.00MiB") == 0.05)
    }

    @Test func ytDlpNonDownloadLinesReturnNil() {
        #expect(parseYtDlpProgress("[youtube] abc123: Downloading webpage") == nil)
        #expect(parseYtDlpProgress("[ExtractAudio] Destination: song.mp3") == nil)
        #expect(parseYtDlpProgress("[download] Destination: video.mp4") == nil)
        #expect(parseYtDlpProgress("") == nil)
        #expect(parseYtDlpProgress("50%") == nil)
    }

    // MARK: - whisper-cpp

    @Test func whisperProgressLineParses() {
        #expect(parseWhisperProgress("whisper_print_progress_callback: progress =  15%") == 0.15)
        #expect(parseWhisperProgress("whisper_print_progress_callback: progress = 100%") == 1.0)
        #expect(parseWhisperProgress("whisper_print_progress_callback: progress=5%") == 0.05)
    }

    @Test func whisperNonProgressLinesReturnNil() {
        #expect(parseWhisperProgress("whisper_init_from_file_with_params_no_state: loading model") == nil)
        #expect(parseWhisperProgress("[00:00:00.000 --> 00:00:04.000]  Hello world") == nil)
        #expect(parseWhisperProgress("") == nil)
        #expect(parseWhisperProgress("progress without percent") == nil)
    }

    // MARK: - Stream line splitting

    @Test func splitsOnNewlineAndCarriageReturn() {
        let (lines, remainder) = splitStreamLines("a\nb\rc")
        #expect(lines == ["a", "b"])
        #expect(remainder == "c")
    }

    @Test func crlfProducesEmptyIntermediateLine() {
        let (lines, remainder) = splitStreamLines("a\r\nb\n")
        #expect(lines == ["a", "", "b"])
        #expect(remainder == "")
    }

    @Test func noSeparatorIsAllRemainder() {
        let (lines, remainder) = splitStreamLines("partial line")
        #expect(lines.isEmpty)
        #expect(remainder == "partial line")
    }

    @Test func emptyInput() {
        let (lines, remainder) = splitStreamLines("")
        #expect(lines.isEmpty)
        #expect(remainder == "")
    }
}
