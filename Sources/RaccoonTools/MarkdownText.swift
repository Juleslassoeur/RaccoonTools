import SwiftUI
import AppKit

// MARK: - Fenced code block parsing (pure, unit-testable)

enum MarkdownSegment: Equatable {
    case text(String)
    case code(language: String?, code: String)
}

/// Splits a markdown string into plain-text and fenced-code segments.
/// Fences are ``` lines, optionally with a language tag (```swift).
/// An unterminated fence is handled gracefully: the rest is treated as code.
func parseFencedCodeBlocks(_ input: String) -> [MarkdownSegment] {
    var segments: [MarkdownSegment] = []
    var textLines: [String] = []
    var codeLines: [String] = []
    var inCode = false
    var language: String?

    func flushText() {
        let text = textLines.joined(separator: "\n")
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(text))
        }
        textLines = []
    }

    for line in input.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if !inCode, trimmed.hasPrefix("```") {
            flushText()
            let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            language = lang.isEmpty ? nil : lang
            inCode = true
        } else if inCode, trimmed == "```" {
            segments.append(.code(language: language, code: codeLines.joined(separator: "\n")))
            codeLines = []
            language = nil
            inCode = false
        } else if inCode {
            codeLines.append(line)
        } else {
            textLines.append(line)
        }
    }

    if inCode {
        // Unterminated fence: treat the rest as code
        segments.append(.code(language: language, code: codeLines.joined(separator: "\n")))
    } else {
        flushText()
    }
    return segments
}

// MARK: - Markdown rendering view

/// Renders an assistant message: fenced code blocks get a monospaced box
/// with a copy button, other text gets inline markdown styling
/// (bold/italic/inline code/links). While a message is still streaming,
/// pass `isStreaming: true` to render plain text and skip re-parsing
/// markdown on every token.
struct MarkdownText: View {
    let text: String
    var isStreaming: Bool = false

    var body: some View {
        if isStreaming {
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parseFencedCodeBlocks(text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let str):
                        inlineMarkdown(str)
                    case .code(let language, let code):
                        CodeBlockView(language: language, code: code)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inlineMarkdown(_ str: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: str,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.caption)
                .textSelection(.enabled)
        } else {
            Text(str)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

/// A fenced code block: monospaced text in a rounded box with a copy button.
struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let language {
                    Text(language)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(code)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}
