import Testing
@testable import RaccoonTools

@Suite struct MarkdownParsingTests {

    @Test func noFencesReturnsSingleTextSegment() {
        let input = "Hello **world**, just some\ninline markdown."
        #expect(parseFencedCodeBlocks(input) == [.text(input)])
    }

    @Test func emptyInputReturnsNoSegments() {
        #expect(parseFencedCodeBlocks("").isEmpty)
        #expect(parseFencedCodeBlocks("   \n  ").isEmpty)
    }

    @Test func singleFencedBlockWithLanguageTag() {
        let input = """
        Here is some code:
        ```swift
        let x = 1
        print(x)
        ```
        Done.
        """
        let segments = parseFencedCodeBlocks(input)
        #expect(segments == [
            .text("Here is some code:"),
            .code(language: "swift", code: "let x = 1\nprint(x)"),
            .text("Done."),
        ])
    }

    @Test func fenceWithoutLanguageTagHasNilLanguage() {
        let input = "```\nplain code\n```"
        #expect(parseFencedCodeBlocks(input) == [.code(language: nil, code: "plain code")])
    }

    @Test func multipleBlocks() {
        let input = """
        First:
        ```python
        a = 1
        ```
        Between blocks.
        ```js
        const b = 2;
        ```
        """
        let segments = parseFencedCodeBlocks(input)
        #expect(segments == [
            .text("First:"),
            .code(language: "python", code: "a = 1"),
            .text("Between blocks."),
            .code(language: "js", code: "const b = 2;"),
        ])
    }

    @Test func unterminatedFenceTreatsRestAsCode() {
        let input = """
        Look:
        ```bash
        echo hi
        echo bye
        """
        let segments = parseFencedCodeBlocks(input)
        #expect(segments == [
            .text("Look:"),
            .code(language: "bash", code: "echo hi\necho bye"),
        ])
    }

    @Test func codeOnlyMessage() {
        let input = "```\nx\n```"
        #expect(parseFencedCodeBlocks(input) == [.code(language: nil, code: "x")])
    }

    @Test func blankTextBetweenBlocksIsDropped() {
        let input = "```\na\n```\n\n```\nb\n```"
        #expect(parseFencedCodeBlocks(input) == [
            .code(language: nil, code: "a"),
            .code(language: nil, code: "b"),
        ])
    }
}
