import Testing
@testable import RaccoonTools

struct TranslateTests {
    @Test func normalizeAcceptsCodesNamesAndColon() {
        #expect(TranslateLang.normalize("en") == "en")
        #expect(TranslateLang.normalize("EN") == "en")
        #expect(TranslateLang.normalize("english") == "en")
        #expect(TranslateLang.normalize("anglais") == "en")
        #expect(TranslateLang.normalize(":es") == "es")
        #expect(TranslateLang.normalize("español") == "es")
        #expect(TranslateLang.normalize("klingon") == nil)
    }

    @Test func trailingColonCodeWins() {
        let r = parseTranslateInput("bonjour le monde :en", default: "fr")
        #expect(r == TranslateRequest(text: "bonjour le monde", target: "en"))
    }

    @Test func trailingColonName() {
        let r = parseTranslateInput("hello world :spanish", default: "fr")
        #expect(r == TranslateRequest(text: "hello world", target: "es"))
    }

    @Test func trailingLanguageWord() {
        let r = parseTranslateInput("poisson english", default: "fr")
        #expect(r == TranslateRequest(text: "poisson", target: "en"))
    }

    @Test func trailingBareCode() {
        let r = parseTranslateInput("bonjour fr", default: "en")
        // "fr" is a recognized code and there's text before it
        #expect(r == TranslateRequest(text: "bonjour", target: "fr"))
    }

    @Test func contextualColonFormFromSelection() {
        // What executeTool builds for selected text + typed "es"
        let r = parseTranslateInput("Some selected sentence. :es", default: "fr")
        #expect(r == TranslateRequest(text: "Some selected sentence.", target: "es"))
    }

    @Test func noLanguageUsesDefault() {
        let r = parseTranslateInput("just some text", default: "fr")
        #expect(r == TranslateRequest(text: "just some text", target: "fr"))
    }

    @Test func singleWordIsTextNotLanguage() {
        // A lone "en" with no preceding text is the text, not a target
        let r = parseTranslateInput("en", default: "fr")
        #expect(r == TranslateRequest(text: "en", target: "fr"))
    }

    @Test func unknownTrailingWordStaysInText() {
        let r = parseTranslateInput("the cat is black", default: "fr")
        #expect(r == TranslateRequest(text: "the cat is black", target: "fr"))
    }
}
