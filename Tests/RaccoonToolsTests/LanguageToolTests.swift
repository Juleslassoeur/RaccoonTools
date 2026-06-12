import Foundation
import Testing
@testable import RaccoonTools

struct LanguageToolTests {
    private func response(_ matches: [(offset: Int, length: Int, value: String, issueType: String)]) -> Data {
        let items = matches.map { m in
            """
            {"offset": \(m.offset), "length": \(m.length),
             "replacements": [{"value": "\(m.value)"}],
             "rule": {"issueType": "\(m.issueType)"}}
            """
        }.joined(separator: ",")
        return "{\"matches\": [\(items)]}".data(using: .utf8)!
    }

    @Test func parsesMatches() {
        let data = response([(offset: 0, length: 3, value: "The", issueType: "misspelling")])
        let corrections = LanguageTool.parseCorrections(data)
        #expect(corrections == [LanguageTool.Correction(offset: 0, length: 3, replacement: "The", isSpelling: true)])
    }

    @Test func skipsMatchesWithoutReplacements() {
        let data = "{\"matches\": [{\"offset\": 0, \"length\": 3, \"replacements\": [], \"rule\": {}}]}".data(using: .utf8)!
        #expect(LanguageTool.parseCorrections(data).isEmpty)
    }

    @Test func appliesCorrectionsRightToLeft() {
        let text = "Teh cat eatts food"
        let corrections = [
            LanguageTool.Correction(offset: 0, length: 3, replacement: "The", isSpelling: true),
            LanguageTool.Correction(offset: 8, length: 5, replacement: "eats", isSpelling: true),
        ]
        #expect(LanguageTool.apply(corrections, to: text, onlySpelling: false) == "The cat eats food")
    }

    @Test func onlySpellingFiltersGrammarFixes() {
        let text = "Teh cat eat food"
        let corrections = [
            LanguageTool.Correction(offset: 0, length: 3, replacement: "The", isSpelling: true),
            LanguageTool.Correction(offset: 8, length: 3, replacement: "eats", isSpelling: false),
        ]
        #expect(LanguageTool.apply(corrections, to: text, onlySpelling: true) == "The cat eat food")
        #expect(LanguageTool.apply(corrections, to: text, onlySpelling: false) == "The cat eats food")
    }

    @Test func utf16OffsetsHandleAccents() {
        // "café" — é is one UTF-16 unit here; LT offsets are UTF-16 based
        let text = "le café cest bon"
        let corrections = [
            LanguageTool.Correction(offset: 8, length: 4, replacement: "c'est", isSpelling: false),
        ]
        #expect(LanguageTool.apply(corrections, to: text, onlySpelling: false) == "le café c'est bon")
    }

    @Test func overlappingCorrectionsKeepTheFirst() {
        let text = "abcdef"
        let corrections = [
            LanguageTool.Correction(offset: 0, length: 4, replacement: "X", isSpelling: true),
            LanguageTool.Correction(offset: 2, length: 3, replacement: "Y", isSpelling: true),
        ]
        #expect(LanguageTool.apply(corrections, to: text, onlySpelling: false) == "Xef")
    }

    @Test func outOfBoundsCorrectionIsIgnored() {
        let corrections = [LanguageTool.Correction(offset: 10, length: 5, replacement: "x", isSpelling: true)]
        #expect(LanguageTool.apply(corrections, to: "short", onlySpelling: false) == "short")
    }

    @Test func garbageJSONYieldsNoCorrections() {
        #expect(LanguageTool.parseCorrections(Data("nope".utf8)).isEmpty)
    }
}
