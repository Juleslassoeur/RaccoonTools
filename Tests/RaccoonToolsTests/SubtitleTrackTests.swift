import Testing
@testable import RaccoonTools

struct SubtitleTrackTests {
    private func json(manual: [String], auto: [String], language: String? = nil) -> String {
        let manualDict = manual.map { "\"\($0)\": []" }.joined(separator: ",")
        let autoDict = auto.map { "\"\($0)\": []" }.joined(separator: ",")
        let lang = language.map { ", \"language\": \"\($0)\"" } ?? ""
        return "{\"subtitles\": {\(manualDict)}, \"automatic_captions\": {\(autoDict)}\(lang)}"
    }

    @Test func prefersManualInPreferredLanguage() {
        let info = json(manual: ["en", "fr"], auto: ["fr-orig"])
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["fr", "en"])
        #expect(choice == SubtitleTrackChoice(lang: "fr", isAutomatic: false))
    }

    @Test func anyManualBeatsAutoTracks() {
        let info = json(manual: ["de"], auto: ["fr-orig", "en"])
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["fr", "en"])
        #expect(choice == SubtitleTrackChoice(lang: "de", isAutomatic: false))
    }

    @Test func autoOriginalTrackBeatsTranslations() {
        // French video, no manual subs: take fr-orig, NOT the rate-limited
        // en translation even though en is preferred
        let info = json(manual: [], auto: ["en", "fr-orig", "es"])
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["en"])
        #expect(choice == SubtitleTrackChoice(lang: "fr-orig", isAutomatic: true))
    }

    @Test func videoLanguageMatchWhenNoOrigTrack() {
        let info = json(manual: [], auto: ["en", "fr"], language: "fr")
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["en"])
        #expect(choice == SubtitleTrackChoice(lang: "fr", isAutomatic: true))
    }

    @Test func regionalVariantMatches() {
        let info = json(manual: ["en-GB"], auto: [])
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["en"])
        #expect(choice == SubtitleTrackChoice(lang: "en-GB", isAutomatic: false))
    }

    @Test func noTracksReturnsNil() {
        #expect(chooseSubtitleTrack(infoJSON: json(manual: [], auto: []), preferred: ["en"]) == nil)
    }

    @Test func garbageInputReturnsNil() {
        #expect(chooseSubtitleTrack(infoJSON: "not json at all", preferred: ["en"]) == nil)
    }

    @Test func warningTextBeforeJSONIsTolerated() {
        let info = "WARNING: something noisy\n" + json(manual: ["fr"], auto: [])
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["fr"])
        #expect(choice == SubtitleTrackChoice(lang: "fr", isAutomatic: false))
    }

    @Test func rawControlCharactersAreStripped() {
        // yt-dlp -J dumps can embed raw control chars that strict parsers reject
        let info = "{\"subtitles\": {\"fr\": []}, \"automatic_captions\": {}, \"x\": \"a\u{05}b\"}"
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["fr"])
        #expect(choice == SubtitleTrackChoice(lang: "fr", isAutomatic: false))
    }

    @Test func emptyPreferredLanguagesAreIgnored() {
        let info = json(manual: ["it"], auto: [])
        let choice = chooseSubtitleTrack(infoJSON: info, preferred: ["", "it"])
        #expect(choice == SubtitleTrackChoice(lang: "it", isAutomatic: false))
    }
}
