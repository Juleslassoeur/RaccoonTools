import Foundation

// Parsing of the contextual assistant's "EDIT:" / "ANSWER:" reply protocol (free mode).

enum FreeReply: Equatable {
    case edit(String)
    case answer(String)
}

enum FreeReplyParser {
    /// Tolerant parse of a complete reply: trims whitespace, accepts the prefix
    /// case-insensitively and after leading newlines. A reply with neither prefix
    /// is treated as an answer — never as an edit, so a malformed response can
    /// never be pasted into the user's document.
    static func parse(_ response: String) -> FreeReply {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        if upper.hasPrefix("EDIT:") {
            return .edit(String(trimmed.dropFirst("EDIT:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if upper.hasPrefix("ANSWER:") {
            return .answer(String(trimmed.dropFirst("ANSWER:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .answer(trimmed)
    }
}

/// Buffers streaming deltas until the EDIT/ANSWER decision can be made (the first
/// few non-whitespace characters), then passes the remaining text through.
final class FreeReplyStreamDecider {
    enum Kind { case edit, answer }

    private(set) var kind: Kind?
    private var buffer = ""

    /// Number of non-whitespace characters that rules out both prefixes
    /// ("ANSWER:" is the longest at 7 characters).
    private static let decisionThreshold = 8

    /// Feed one delta. Returns text to display once the reply kind is decided,
    /// nil while still buffering.
    func ingest(_ delta: String) -> String? {
        if kind != nil { return delta }
        buffer += delta
        let trimmed = String(buffer.drop(while: { $0.isWhitespace }))
        let upper = trimmed.uppercased()
        if upper.hasPrefix("EDIT:") {
            kind = .edit
            return String(trimmed.dropFirst("EDIT:".count).drop(while: { $0.isWhitespace }))
        }
        if upper.hasPrefix("ANSWER:") {
            kind = .answer
            return String(trimmed.dropFirst("ANSWER:".count).drop(while: { $0.isWhitespace }))
        }
        if trimmed.filter({ !$0.isWhitespace }).count >= Self.decisionThreshold {
            kind = .answer
            return trimmed
        }
        return nil
    }

    /// Call when the stream ends. If still undecided, falls back to ANSWER and
    /// returns the leftover buffered text (nil if there is none).
    func finish() -> String? {
        guard kind == nil else { return nil }
        kind = .answer
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return leftover.isEmpty ? nil : leftover
    }
}
