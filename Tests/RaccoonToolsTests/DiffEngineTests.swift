import Testing
import Foundation
@testable import RaccoonTools

@Suite struct DiffEngineTests {

    // MARK: - Tokenization

    @Test func tokenizeSplitsOnWhitespaceKeepingPunctuation() {
        #expect(DiffEngine.tokenize("Hello, world!  How are\nyou?") == ["Hello,", "world!", "How", "are", "you?"])
        #expect(DiffEngine.tokenize("") == [])
        #expect(DiffEngine.tokenize("   \n\t ") == [])
        #expect(DiffEngine.tokenize("one") == ["one"])
    }

    // MARK: - Diff

    @Test func identicalTextsYieldSingleEqualSegment() {
        let segments = DiffEngine.diff(original: "the quick brown fox", edited: "the quick brown fox")
        #expect(segments == [DiffSegment(kind: .equal, text: "the quick brown fox")])
    }

    @Test func emptyToEmptyYieldsNoSegments() {
        #expect(DiffEngine.diff(original: "", edited: "").isEmpty)
    }

    @Test func pureInsertion() {
        let segments = DiffEngine.diff(original: "", edited: "hello world")
        #expect(segments == [DiffSegment(kind: .inserted, text: "hello world")])
    }

    @Test func pureDeletion() {
        let segments = DiffEngine.diff(original: "hello world", edited: "")
        #expect(segments == [DiffSegment(kind: .deleted, text: "hello world")])
    }

    @Test func wordReplacementProducesDeleteAndInsert() {
        let segments = DiffEngine.diff(original: "the quick brown fox", edited: "the slow brown fox")
        #expect(segments.contains(DiffSegment(kind: .deleted, text: "quick")))
        #expect(segments.contains(DiffSegment(kind: .inserted, text: "slow")))
        #expect(segments.first == DiffSegment(kind: .equal, text: "the"))
        #expect(segments.last == DiffSegment(kind: .equal, text: "brown fox"))
    }

    @Test func consecutiveChangesAreMergedIntoOneSegment() {
        let segments = DiffEngine.diff(original: "a b c d e", edited: "a x y z e")
        // Middle run "b c d" deleted, "x y z" inserted — each as one segment
        let deleted = segments.filter { $0.kind == .deleted }
        let inserted = segments.filter { $0.kind == .inserted }
        #expect(deleted == [DiffSegment(kind: .deleted, text: "b c d")])
        #expect(inserted == [DiffSegment(kind: .inserted, text: "x y z")])
    }

    @Test func equalAndDeletedSegmentsReconstructOriginal() {
        let original = "The meeting is at noon, please bring your notes and a laptop."
        let edited = "The meeting is at 2pm, please bring your printed notes."
        let segments = DiffEngine.diff(original: original, edited: edited)
        let reconstructedOriginal = segments
            .filter { $0.kind != .inserted }
            .map(\.text)
            .joined(separator: " ")
        let reconstructedEdited = segments
            .filter { $0.kind != .deleted }
            .map(\.text)
            .joined(separator: " ")
        #expect(reconstructedOriginal == DiffEngine.tokenize(original).joined(separator: " "))
        #expect(reconstructedEdited == DiffEngine.tokenize(edited).joined(separator: " "))
    }

    @Test func diffNeverEmitsEmptySegments() {
        let segments = DiffEngine.diff(original: "a b c", edited: "x y z")
        #expect(segments.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: - Similarity

    @Test func similarityOfIdenticalTextsIsOne() {
        #expect(DiffEngine.similarity(original: "one two three", edited: "one two three") == 1.0)
    }

    @Test func similarityOfDisjointTextsIsZero() {
        #expect(DiffEngine.similarity(original: "alpha beta gamma", edited: "uno dos tres") == 0.0)
    }

    @Test func similarityOfBothEmptyIsOne() {
        #expect(DiffEngine.similarity(original: "", edited: "") == 1.0)
    }

    @Test func similarityWithOneEmptySideIsZero() {
        #expect(DiffEngine.similarity(original: "some words here", edited: "") == 0.0)
        #expect(DiffEngine.similarity(original: "", edited: "some words here") == 0.0)
    }

    @Test func similarityIsCommonTokensOverMaxCount() {
        // original: 4 tokens, edited: 4 tokens, LCS = "a b c" (3) → 3/4
        let value = DiffEngine.similarity(original: "a b c d", edited: "a b c x")
        #expect(abs(value - 0.75) < 0.0001)
    }

    // MARK: - Gating decision

    /// 14 words, > 80 characters — comfortably above the size thresholds.
    private let longOriginal = "The committee decided yesterday afternoon that the proposal should be reviewed again next quarter."

    @Test func gatingAcceptsPartialRewordOfLongText() {
        // Change a few words: similarity stays high
        let edited = "The committee agreed yesterday afternoon that the proposal must be reviewed again next quarter."
        #expect(DiffEngine.tokenize(longOriginal).count >= DiffEngine.diffMinimumWordCount)
        #expect(longOriginal.count >= DiffEngine.diffMinimumCharacterCount)
        #expect(DiffEngine.shouldShowDiff(original: longOriginal, edited: edited))
    }

    @Test func gatingRejectsShortOriginalByWordCount() {
        // 11 words but > 80 chars — fails the ≥ 12 words requirement
        let original = "Extraordinarily complicated considerations regarding intercontinental transportation infrastructure modernization throughout western Europe"
        #expect(DiffEngine.tokenize(original).count < DiffEngine.diffMinimumWordCount)
        #expect(original.count >= DiffEngine.diffMinimumCharacterCount)
        #expect(!DiffEngine.shouldShowDiff(original: original, edited: original))
    }

    @Test func gatingRejectsShortOriginalByCharacterCount() {
        // 13 words but < 80 characters — fails the ≥ 80 chars requirement
        let original = "a b c d e f g h i j k l m"
        #expect(DiffEngine.tokenize(original).count >= DiffEngine.diffMinimumWordCount)
        #expect(original.count < DiffEngine.diffMinimumCharacterCount)
        #expect(!DiffEngine.shouldShowDiff(original: original, edited: original))
    }

    @Test func gatingRejectsFullReplacement() {
        // Same length but no token in common → similarity 0 < 0.35
        let edited = "Bonjour tout le monde, ceci est une phrase totalement differente sans aucun mot commun ici."
        #expect(!DiffEngine.shouldShowDiff(original: longOriginal, edited: edited))
    }

    @Test func gatingRejectsEmptyEdit() {
        #expect(!DiffEngine.shouldShowDiff(original: longOriginal, edited: ""))
    }

    @Test func gatingUsesSimilarityThreshold() {
        // Build originals/edits straddling the 0.35 boundary precisely.
        // 20 tokens, keep 8 in place → similarity 0.4 ≥ 0.35 → diff shown
        let originalTokens = (1...20).map { "word\($0)x" }
        let original = originalTokens.joined(separator: " ")
        #expect(original.count >= DiffEngine.diffMinimumCharacterCount)

        var mostlyKept = originalTokens
        for i in 8..<20 { mostlyKept[i] = "new\(i)" }
        #expect(DiffEngine.shouldShowDiff(original: original, edited: mostlyKept.joined(separator: " ")))

        // Keep only 6 of 20 → similarity 0.3 < 0.35 → plain text
        var mostlyReplaced = originalTokens
        for i in 6..<20 { mostlyReplaced[i] = "new\(i)" }
        #expect(!DiffEngine.shouldShowDiff(original: original, edited: mostlyReplaced.joined(separator: " ")))
    }

    @Test func gatingRejectsHugeTexts() {
        let huge = Array(repeating: "tokenword", count: DiffEngine.diffMaximumTokenCount + 1).joined(separator: " ")
        #expect(!DiffEngine.shouldShowDiff(original: huge, edited: huge))
    }
}
