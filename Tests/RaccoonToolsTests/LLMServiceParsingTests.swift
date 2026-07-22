import Testing
import Foundation
@testable import RaccoonTools

@Suite struct LLMServiceParsingTests {

    // MARK: - SSE line parsing

    @Test func sseDataPayloadExtractsData() {
        #expect(LLMService.sseDataPayload("data: {\"x\":1}") == "{\"x\":1}")
        #expect(LLMService.sseDataPayload("data: [DONE]") == "[DONE]")
    }

    @Test func sseDataPayloadIgnoresNonDataLines() {
        #expect(LLMService.sseDataPayload("event: message_start") == nil)
        #expect(LLMService.sseDataPayload("") == nil)
        #expect(LLMService.sseDataPayload(": keep-alive") == nil)
    }

    // MARK: - Claude stream events

    @Test func claudeTextDelta() {
        let payload = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        let event = LLMService.claudeStreamEvent(payload)
        #expect(event.text == "Hello")
        #expect(event.stop == false)
    }

    @Test func claudeMessageStop() {
        let event = LLMService.claudeStreamEvent(#"{"type":"message_stop"}"#)
        #expect(event.text == nil)
        #expect(event.stop == true)
    }

    @Test func claudeNonTextEventsAreIgnored() {
        let thinking = #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}"#
        #expect(LLMService.claudeStreamEvent(thinking).text == nil)
        #expect(LLMService.claudeStreamEvent(#"{"type":"ping"}"#).text == nil)
        #expect(LLMService.claudeStreamEvent("not json").text == nil)
    }

    // MARK: - OpenAI stream chunks

    @Test func openAIDelta() {
        let payload = #"{"choices":[{"delta":{"content":"Hi"},"index":0}]}"#
        #expect(LLMService.openAIStreamDelta(payload) == "Hi")
    }

    @Test func openAIRoleAndFinishChunksAreIgnored() {
        #expect(LLMService.openAIStreamDelta(#"{"choices":[{"delta":{"role":"assistant"}}]}"#) == nil)
        #expect(LLMService.openAIStreamDelta(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == nil)
    }

    // MARK: - Gemini stream chunks

    @Test func geminiDelta() {
        let payload = #"{"candidates":[{"content":{"parts":[{"text":"Salut"}],"role":"model"}}]}"#
        #expect(LLMService.geminiStreamDelta(payload) == "Salut")
    }

    @Test func geminiChunkWithoutTextIsIgnored() {
        #expect(LLMService.geminiStreamDelta(#"{"usageMetadata":{"totalTokenCount":3}}"#) == nil)
    }

    // MARK: - Ollama NDJSON chunks

    @Test func ollamaChunk() {
        let line = #"{"model":"llama3.2","message":{"role":"assistant","content":"Hey"},"done":false}"#
        let chunk = LLMService.ollamaStreamChunk(line)
        #expect(chunk.text == "Hey")
        #expect(chunk.done == false)
    }

    @Test func ollamaDoneChunk() {
        let chunk = LLMService.ollamaStreamChunk(#"{"model":"llama3.2","message":{"role":"assistant","content":""},"done":true}"#)
        #expect(chunk.done == true)
    }

    // MARK: - Error body parsing

    @Test func apiErrorMessageParsesNestedError() {
        let body = Data(#"{"error":{"type":"invalid_request_error","message":"max_tokens too large"}}"#.utf8)
        #expect(LLMService.apiErrorMessage(fromBody: body) == "max_tokens too large")
    }

    @Test func apiErrorMessageParsesOllamaStyle() {
        let body = Data(#"{"error":"model not found"}"#.utf8)
        #expect(LLMService.apiErrorMessage(fromBody: body) == "model not found")
    }

    @Test func apiErrorMessageFallsBackToRawBody() {
        #expect(LLMService.apiErrorMessage(fromBody: Data("Bad Gateway".utf8)) == "Bad Gateway")
        #expect(LLMService.apiErrorMessage(fromBody: Data()) == "no error details")
    }

    // MARK: - History normalization

    @Test func normalizedHistoryDropsLeadingAssistantTurns() {
        let turns = LLMService.normalizedHistory([
            LLMMessage(role: .assistant, content: "tool result"),
            LLMMessage(role: .user, content: "shorten it"),
        ])
        #expect(turns.count == 1)
        #expect(turns[0].role == .user)
    }

    @Test func normalizedHistoryMergesConsecutiveSameRole() {
        let turns = LLMService.normalizedHistory([
            LLMMessage(role: .user, content: "a"),
            LLMMessage(role: .user, content: "b"),
            LLMMessage(role: .assistant, content: "c"),
        ])
        #expect(turns.count == 2)
        #expect(turns[0].content == "a\n\nb")
        #expect(turns[1].role == .assistant)
    }

    @Test func normalizedHistorySkipsEmptyMessages() {
        let turns = LLMService.normalizedHistory([
            LLMMessage(role: .user, content: "hello"),
            LLMMessage(role: .assistant, content: "  \n"),
            LLMMessage(role: .user, content: "again"),
        ])
        #expect(turns.count == 1)
        #expect(turns[0].content == "hello\n\nagain")
    }

    @Test func errorDescriptionsAreReadable() {
        #expect(LLMError.noProvider.errorDescription?.contains("Settings > Tools") == true)
        #expect(LLMError.noAPIKey("Claude").errorDescription?.contains("Claude") == true)
        #expect(LLMError.api(status: 429, message: "rate limited").errorDescription == "API Error (429): rate limited")
    }

    // Gemini 2.5 disables thinking via thinkingBudget, Gemini 3 rejects it (400)
    // and expects thinkingLevel, older models accept neither: the fallback chain
    // must keep this exact order and end with "no thinkingConfig".
    @Test func geminiThinkingOffFallbackChain() {
        let configs = LLMService.geminiThinkingOffConfigs
        #expect(configs.count == 3)
        #expect(configs[0]?["thinkingBudget"] as? Int == 0)
        #expect(configs[1]?["thinkingLevel"] as? String == "minimal")
        #expect(configs[2] == nil)
    }
}
