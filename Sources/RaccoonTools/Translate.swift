import Foundation

/// Pure language-parsing helpers for the translate tool (unit-tested).
///
/// In contextual mode the selected text is the subject and the user only
/// types the target — `translate en`, `translate fr`, `translate es` — so the
/// language is combined with the selection using the unambiguous `:code`
/// suffix. Typed directly in the launcher, `translate <text> <lang>` and
/// `translate <text> :<lang>` both work too.
enum TranslateLang {
    /// Names and codes → ISO code. Limited to the supported set on purpose:
    /// a smaller map keeps the trailing-word heuristic from eating ordinary
    /// words (e.g. English "is", "it").
    static let codes: [String: String] = [
        "english": "en", "anglais": "en", "en": "en",
        "french": "fr", "francais": "fr", "français": "fr", "fr": "fr",
        "spanish": "es", "espagnol": "es", "espanol": "es", "español": "es", "es": "es",
        "german": "de", "allemand": "de", "deutsch": "de", "de": "de",
        "italian": "it", "italien": "it", "italiano": "it", "it": "it",
        "portuguese": "pt", "portugais": "pt", "pt": "pt",
        "chinese": "zh", "chinois": "zh", "zh": "zh",
        "japanese": "ja", "japonais": "ja", "ja": "ja",
        "korean": "ko", "coreen": "ko", "coréen": "ko", "ko": "ko",
        "arabic": "ar", "arabe": "ar", "ar": "ar",
        "russian": "ru", "russe": "ru", "ru": "ru",
        "dutch": "nl", "neerlandais": "nl", "néerlandais": "nl", "nl": "nl",
    ]

    /// Display name for a code, for prompts/messages.
    static let names: [String: String] = [
        "en": "English", "fr": "French", "es": "Spanish", "de": "German",
        "it": "Italian", "pt": "Portuguese", "zh": "Chinese", "ja": "Japanese",
        "ko": "Korean", "ar": "Arabic", "ru": "Russian", "nl": "Dutch",
    ]

    /// Normalizes a language name/code (with or without a leading `:`) to an
    /// ISO code, or nil when unrecognized.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix(":") { s.removeFirst() }
        return codes[s]
    }
}

struct TranslateRequest: Equatable {
    let text: String
    let target: String
}

/// Splits a translate input into (text, target language code). Recognizes a
/// trailing `:code`/`:name`, then a trailing language name/code when other
/// text precedes it; otherwise the whole input is the text and the default
/// target is used.
func parseTranslateInput(_ input: String, default defaultLang: String) -> TranslateRequest {
    let trimmed = input.trimmingCharacters(in: .whitespaces)

    // Trailing ":xx" / ":english" — unambiguous, used by the contextual flow
    if let r = trimmed.range(of: #"\s:\S+$"#, options: .regularExpression) {
        let token = String(trimmed[r]).trimmingCharacters(in: .whitespaces)
        if let code = TranslateLang.normalize(token) {
            let text = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            return TranslateRequest(text: text, target: code)
        }
    }

    // Trailing language word, only when there is text before it
    let words = trimmed.split(separator: " ").map(String.init)
    if words.count >= 2, let last = words.last, let code = TranslateLang.normalize(last) {
        return TranslateRequest(text: words.dropLast().joined(separator: " "), target: code)
    }

    return TranslateRequest(text: trimmed, target: defaultLang)
}
