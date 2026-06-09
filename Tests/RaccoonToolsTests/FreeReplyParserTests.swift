import Testing
import Foundation
@testable import RaccoonTools

@Suite struct FreeReplyParserTests {

    // MARK: - Complete-response parsing

    @Test func parsesEditPrefix() {
        #expect(FreeReplyParser.parse("EDIT: Hello world") == .edit("Hello world"))
    }

    @Test func parsesAnswerPrefix() {
        #expect(FreeReplyParser.parse("ANSWER: It is French.") == .answer("It is French."))
    }

    @Test func prefixIsCaseInsensitive() {
        #expect(FreeReplyParser.parse("edit: fixed text") == .edit("fixed text"))
        #expect(FreeReplyParser.parse("Answer: yes") == .answer("yes"))
    }

    @Test func acceptsPrefixAfterLeadingWhitespaceAndNewlines() {
        #expect(FreeReplyParser.parse("\n\n  EDIT:\nnew text") == .edit("new text"))
    }

    @Test func missingPrefixFallsBackToAnswerNeverEdit() {
        // Safest failure mode: an unprefixed response must never be applied as an edit
        #expect(FreeReplyParser.parse("I rewrote your text for you.") == .answer("I rewrote your text for you."))
    }

    @Test func editPrefixMidTextIsNotAnEdit() {
        #expect(FreeReplyParser.parse("Sure! EDIT: something") == .answer("Sure! EDIT: something"))
    }

    // MARK: - Streaming decider

    @Test func decidesEditAcrossDeltas() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.ingest("ED") == nil)
        #expect(decider.ingest("IT:") == "")
        #expect(decider.kind == .edit)
        #expect(decider.ingest(" Hello") == " Hello")
    }

    @Test func decidesAnswerAcrossDeltas() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.ingest("ANSW") == nil)
        #expect(decider.ingest("ER: Oui") == "Oui")
        #expect(decider.kind == .answer)
    }

    @Test func stripsLeadingWhitespaceAfterPrefix() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.ingest("EDIT:\n  Bonjour") == "Bonjour")
        #expect(decider.kind == .edit)
    }

    @Test func unprefixedTextDecidesAnswerAfterThreshold() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.ingest("The ") == nil)
        let emitted = decider.ingest("text is in French")
        #expect(emitted == "The text is in French")
        #expect(decider.kind == .answer)
    }

    @Test func leadingWhitespaceDoesNotCountTowardDecision() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.ingest("\n\n   ") == nil)
        #expect(decider.ingest("EDIT: ok") == "ok")
        #expect(decider.kind == .edit)
    }

    @Test func shortStreamFallsBackToAnswerOnFinish() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.ingest("Oui.") == nil)
        #expect(decider.finish() == "Oui.")
        #expect(decider.kind == .answer)
    }

    @Test func finishAfterDecisionReturnsNothing() {
        let decider = FreeReplyStreamDecider()
        _ = decider.ingest("ANSWER: hello there")
        #expect(decider.finish() == nil)
    }

    @Test func emptyStreamFinishReturnsNil() {
        let decider = FreeReplyStreamDecider()
        #expect(decider.finish() == nil)
        #expect(decider.kind == .answer)
    }
}
