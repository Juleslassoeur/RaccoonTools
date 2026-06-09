import Testing
@testable import RaccoonTools

@Suite struct VttToPlainTextTests {

    @Test func stripsHeadersTimestampsAndDuplicateCueLines() {
        // Realistic YouTube auto-sub style VTT
        let vtt = """
        WEBVTT
        Kind: captions
        Language: en

        00:00:00.000 --> 00:00:02.500 align:start position:0%
        hello world
        hello world

        00:00:02.500 --> 00:00:05.000 align:start position:0%
        hello world
        this is a test

        3
        00:00:05.000 --> 00:00:07.000
        <c.colorE5E5E5>styled</c> <b>text</b>
        """
        #expect(vttToPlainText(vtt) == "hello world\nthis is a test\nstyled text")
    }

    @Test func skipsNumericOnlyLinesAndTimestampFragments() {
        let vtt = """
        WEBVTT

        1
        00:00:01.000
        real line
        """
        // Cue index "1" and the bare timestamp contain only digits/:/. — both stripped
        #expect(vttToPlainText(vtt) == "real line")
    }

    @Test func onlyConsecutiveDuplicatesAreRemoved() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        alpha

        00:00:01.000 --> 00:00:02.000
        beta

        00:00:02.000 --> 00:00:03.000
        alpha
        """
        // Non-consecutive repeats are kept; only immediate repeats collapse
        #expect(vttToPlainText(vtt) == "alpha\nbeta\nalpha")
    }

    @Test func htmlTagsRemovedAndTagOnlyLinesDropped() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        <00:00:00.500><c>word</c>
        <c></c>
        """
        // Inline timing/styling tags are stripped; a line that becomes empty is dropped
        #expect(vttToPlainText(vtt) == "word")
    }

    @Test func emptyInputProducesEmptyOutput() {
        #expect(vttToPlainText("") == "")
        #expect(vttToPlainText("WEBVTT\n\n") == "")
    }
}
