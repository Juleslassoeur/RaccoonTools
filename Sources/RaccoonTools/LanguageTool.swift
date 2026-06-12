import Foundation

/// Free grammar/spelling engine backed by the public LanguageTool API
/// (api.languagetool.org — no key, ~20 req/min, 20k chars per request).
/// Used as an optional alternative to the LLM for `fix grammar` / `fix orth`.
enum LanguageTool {
    struct Correction: Equatable {
        let offset: Int      // UTF-16 offsets, as returned by the API
        let length: Int
        let replacement: String
        let isSpelling: Bool
    }

    static let maxTextLength = 20_000

    /// Parses the /v2/check JSON into corrections (first suggestion of each
    /// match; matches without suggestions are skipped). Pure, unit-testable.
    static func parseCorrections(_ data: Data) -> [Correction] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let matches = json["matches"] as? [[String: Any]] else { return [] }
        return matches.compactMap { match in
            guard let offset = match["offset"] as? Int,
                  let length = match["length"] as? Int, length > 0,
                  let replacements = match["replacements"] as? [[String: Any]],
                  let value = replacements.first?["value"] as? String else { return nil }
            let rule = match["rule"] as? [String: Any]
            let issueType = (rule?["issueType"] as? String) ?? ""
            return Correction(offset: offset, length: length, replacement: value,
                              isSpelling: issueType == "misspelling")
        }
    }

    /// Applies corrections right-to-left so earlier offsets stay valid.
    /// Overlapping corrections keep the first (leftmost) one. Pure.
    static func apply(_ corrections: [Correction], to text: String, onlySpelling: Bool) -> String {
        let kept = corrections
            .filter { !onlySpelling || $0.isSpelling }
            .sorted { $0.offset < $1.offset }
        // Drop overlaps
        var nonOverlapping: [Correction] = []
        var lastEnd = -1
        for c in kept {
            guard c.offset >= lastEnd else { continue }
            nonOverlapping.append(c)
            lastEnd = c.offset + c.length
        }

        let ns = NSMutableString(string: text)
        for c in nonOverlapping.reversed() {
            guard c.offset + c.length <= ns.length else { continue }
            ns.replaceCharacters(in: NSRange(location: c.offset, length: c.length), with: c.replacement)
        }
        return ns as String
    }

    /// Full round trip: check + apply. Language is auto-detected.
    static func correct(_ text: String, onlySpelling: Bool) async throws -> String {
        guard text.utf16.count <= maxTextLength else {
            throw ToolError.failed("text too long for the free LanguageTool API (max ~20k characters) — use the LLM engine")
        }

        var req = URLRequest(url: URL(string: "https://api.languagetool.org/v2/check")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        req.httpBody = "text=\(encoded)&language=auto".data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw ToolError.failed("LanguageTool API error (HTTP \(code))" + (code == 429 ? " — rate limited, retry in a minute" : ""))
        }
        return apply(parseCorrections(data), to: text, onlySpelling: onlySpelling)
    }
}
