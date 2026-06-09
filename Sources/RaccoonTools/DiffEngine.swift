import Foundation

// Word-level diff used by the free-mode edit card. Pure logic, no UI.

enum DiffSegmentKind: Equatable {
    case equal
    case inserted
    case deleted
}

/// One run of consecutive tokens sharing the same diff kind.
/// `text` is the tokens of the run joined with single spaces.
struct DiffSegment: Equatable {
    let kind: DiffSegmentKind
    let text: String
}

enum DiffEngine {

    // MARK: - Gating thresholds

    /// Diff rendering only makes sense for a partial rewording of a reasonably
    /// long text. Below these sizes (or below the similarity floor, i.e. a full
    /// replacement) the plain edited text is shown instead.
    static let diffMinimumWordCount = 12
    static let diffMinimumCharacterCount = 80
    static let diffMinimumSimilarity = 0.35
    /// Safety cap: above this many tokens the O(n·m) LCS isn't worth computing.
    static let diffMaximumTokenCount = 1500

    // MARK: - Tokenization

    /// Splits on whitespace; punctuation stays attached to its word.
    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    // MARK: - Similarity

    /// Token-level similarity: LCS common tokens / max token count.
    /// 1.0 = identical token sequences, 0.0 = nothing in common.
    static func similarity(original: String, edited: String) -> Double {
        let a = tokenize(original)
        let b = tokenize(edited)
        if a.isEmpty && b.isEmpty { return 1.0 }
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }
        let common = lcsTable(a, b)[a.count][b.count]
        return Double(common) / Double(max(a.count, b.count))
    }

    // MARK: - Gating decision

    /// Whether the edit card should render a word-level diff instead of plain
    /// text. True only when the original is long enough (≥ 12 words and ≥ 80
    /// characters) AND the edit is a partial rewording (similarity ≥ 0.35) —
    /// never for short selections or full replacements.
    static func shouldShowDiff(original: String, edited: String) -> Bool {
        let originalTokens = tokenize(original)
        let editedTokens = tokenize(edited)
        guard originalTokens.count >= diffMinimumWordCount else { return false }
        guard original.count >= diffMinimumCharacterCount else { return false }
        guard !editedTokens.isEmpty else { return false }
        guard originalTokens.count <= diffMaximumTokenCount,
              editedTokens.count <= diffMaximumTokenCount else { return false }
        return similarity(original: original, edited: edited) >= diffMinimumSimilarity
    }

    // MARK: - Diff

    /// Token-level diff of original → edited using LCS. Consecutive tokens of
    /// the same kind are merged into a single segment.
    static func diff(original: String, edited: String) -> [DiffSegment] {
        let a = tokenize(original)
        let b = tokenize(edited)
        let table = lcsTable(a, b)

        // Backtrack from (a.count, b.count) collecting per-token operations.
        var ops: [(kind: DiffSegmentKind, token: String)] = []
        var i = a.count
        var j = b.count
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                ops.append((.equal, a[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || table[i][j - 1] >= table[i - 1][j]) {
                ops.append((.inserted, b[j - 1]))
                j -= 1
            } else {
                ops.append((.deleted, a[i - 1]))
                i -= 1
            }
        }
        ops.reverse()

        // Merge consecutive same-kind tokens into segments.
        var segments: [DiffSegment] = []
        var runKind: DiffSegmentKind?
        var runTokens: [String] = []
        for op in ops {
            if op.kind == runKind {
                runTokens.append(op.token)
            } else {
                if let kind = runKind {
                    segments.append(DiffSegment(kind: kind, text: runTokens.joined(separator: " ")))
                }
                runKind = op.kind
                runTokens = [op.token]
            }
        }
        if let kind = runKind {
            segments.append(DiffSegment(kind: kind, text: runTokens.joined(separator: " ")))
        }
        return segments
    }

    // MARK: - LCS

    /// Classic dynamic-programming LCS length table:
    /// table[i][j] = LCS length of a[0..<i] and b[0..<j].
    private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        guard !a.isEmpty, !b.isEmpty else { return table }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        return table
    }
}
