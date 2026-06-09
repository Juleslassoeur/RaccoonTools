import Testing
import Foundation
@testable import RaccoonTools

@Suite struct LLMProviderConfigTests {

    @Test func decodeWithoutEnableThinkingDefaultsToFalse() throws {
        // Old providers.json files have no "enableThinking" key
        let json = """
        [{"id":"claude","name":"Claude","type":"claude","apiKey":"",
          "model":"claude-sonnet-4-6","baseURL":"https://api.anthropic.com"}]
        """.data(using: .utf8)!
        let configs = try JSONDecoder().decode([LLMProviderConfig].self, from: json)
        #expect(configs.count == 1)
        #expect(configs[0].enableThinking == false)
        #expect(configs[0].id == "claude")
        #expect(configs[0].type == .claude)
    }

    @Test func decodeWithEnableThinkingPresent() throws {
        let json = """
        {"id":"g","name":"Gemini","type":"gemini","apiKey":"k",
         "model":"gemini-2.5-flash","baseURL":"https://generativelanguage.googleapis.com",
         "enableThinking":true}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(LLMProviderConfig.self, from: json)
        #expect(config.enableThinking == true)
        #expect(config.type == .gemini)
    }

    @Test func encodeDecodeRoundTrip() throws {
        var original = LLMProviderConfig.defaultOllama
        original.enableThinking = true
        original.apiKey = "secret"
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMProviderConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func defaultClaude() {
        let p = LLMProviderConfig.defaultClaude
        #expect(p.id == "claude")
        #expect(p.name == "Claude")
        #expect(p.type == .claude)
        #expect(p.apiKey == "")
        #expect(p.model == "claude-sonnet-4-6")
        #expect(p.baseURL == "https://api.anthropic.com")
        #expect(p.enableThinking == false)
    }

    @Test func defaultOpenAI() {
        let p = LLMProviderConfig.defaultOpenAI
        #expect(p.id == "openai")
        #expect(p.type == .openai)
        #expect(p.model == "gpt-4o")
        #expect(p.baseURL == "https://api.openai.com")
    }

    @Test func defaultGemini() {
        let p = LLMProviderConfig.defaultGemini
        #expect(p.id == "gemini")
        #expect(p.type == .gemini)
        #expect(p.model == "gemini-2.5-flash")
        #expect(p.baseURL == "https://generativelanguage.googleapis.com")
    }

    @Test func defaultOllama() {
        let p = LLMProviderConfig.defaultOllama
        #expect(p.id == "ollama")
        #expect(p.type == .ollama)
        #expect(p.model == "llama3.2")
        #expect(p.baseURL == "http://localhost:11434")
    }

    @Test func providerTypeRawValuesStayStable() {
        // Persisted in providers.json — must never change
        #expect(LLMProviderType.claude.rawValue == "claude")
        #expect(LLMProviderType.openai.rawValue == "openai")
        #expect(LLMProviderType.gemini.rawValue == "gemini")
        #expect(LLMProviderType.ollama.rawValue == "ollama")
        #expect(LLMProviderType.custom.rawValue == "custom")
    }
}
