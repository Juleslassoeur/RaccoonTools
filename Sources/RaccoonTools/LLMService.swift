import Foundation

enum LLMProviderType: String, Codable, CaseIterable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"
    case ollama = "ollama"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini (Google)"
        case .ollama: return "Ollama (local)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }
}

struct LLMProviderConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var type: LLMProviderType
    var apiKey: String
    var model: String
    var baseURL: String
    var enableThinking: Bool

    init(id: String, name: String, type: LLMProviderType, apiKey: String, model: String, baseURL: String, enableThinking: Bool = false) {
        self.id = id; self.name = name; self.type = type; self.apiKey = apiKey
        self.model = model; self.baseURL = baseURL; self.enableThinking = enableThinking
    }

    // Handle decoding with missing enableThinking (backward compat)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(LLMProviderType.self, forKey: .type)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        model = try c.decode(String.self, forKey: .model)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        enableThinking = try c.decodeIfPresent(Bool.self, forKey: .enableThinking) ?? false
    }

    static var defaultClaude: LLMProviderConfig {
        .init(id: "claude", name: "Claude", type: .claude, apiKey: "",
              model: "claude-sonnet-4-6", baseURL: "https://api.anthropic.com")
    }

    static let retiredModelMigrations: [String: String] = [
        "claude-sonnet-4-20250514": "claude-sonnet-4-6",
        "claude-opus-4-20250514": "claude-opus-4-8",
        "claude-3-5-sonnet-20241022": "claude-sonnet-4-6",
        "claude-3-5-sonnet-20240620": "claude-sonnet-4-6",
        "claude-3-7-sonnet-20250219": "claude-sonnet-4-6",
        "claude-3-opus-20240229": "claude-opus-4-8",
        "claude-3-5-haiku-20241022": "claude-haiku-4-5",
    ]
    static var defaultOpenAI: LLMProviderConfig {
        .init(id: "openai", name: "OpenAI", type: .openai, apiKey: "",
              model: "gpt-4o", baseURL: "https://api.openai.com")
    }
    static var defaultGemini: LLMProviderConfig {
        .init(id: "gemini", name: "Gemini", type: .gemini, apiKey: "",
              model: "gemini-2.5-flash", baseURL: "https://generativelanguage.googleapis.com")
    }
    static var defaultOllama: LLMProviderConfig {
        .init(id: "ollama", name: "Ollama", type: .ollama, apiKey: "",
              model: "llama3.2", baseURL: "http://localhost:11434")
    }
}

struct ToolLLMBinding: Codable {
    var providerID: String
    var systemPrompt: String
}

// MARK: - Messages & errors

struct LLMMessage {
    enum Role: String {
        case user
        case assistant
    }
    let role: Role
    let content: String
}

enum LLMError: LocalizedError {
    case noProvider
    case noAPIKey(String)
    case api(status: Int, message: String)
    case invalidResponse(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No LLM provider configured for this tool.\nGo to Raccoon Tools > Settings > Tools to configure."
        case .noAPIKey(let providerName):
            return "No API key set for \(providerName).\nGo to Settings > LLM Providers."
        case .api(let status, let message):
            return "API Error (\(status)): \(message)"
        case .invalidResponse(let detail):
            return "Invalid LLM response: \(detail)"
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Service

class LLMService {

    // MARK: Public API

    /// Convenience for one-shot tools: a single user message.
    static func call(provider: LLMProviderConfig?, systemPrompt: String, userMessage: String, maxTokens: Int = 8192) async throws -> String {
        try await call(provider: provider, systemPrompt: systemPrompt,
                       messages: [LLMMessage(role: .user, content: userMessage)],
                       maxTokens: maxTokens)
    }

    /// Non-streaming multi-turn call. Throws LLMError on any failure.
    static func call(provider: LLMProviderConfig?, systemPrompt: String,
                     messages: [LLMMessage], maxTokens: Int = 8192,
                     injectResponseLanguage: Bool = true) async throws -> String {
        let (p, system, turns) = try prepare(provider, systemPrompt: systemPrompt, messages: messages,
                                             injectResponseLanguage: injectResponseLanguage)
        switch p.type {
        case .claude: return try await callClaude(p, system: system, messages: turns, maxTokens: maxTokens)
        case .openai, .custom: return try await callOpenAI(p, system: system, messages: turns)
        case .gemini: return try await callGemini(p, system: system, messages: turns)
        case .ollama: return try await callOllama(p, system: system, messages: turns)
        }
    }

    /// Streaming multi-turn call: invokes onDelta with each text fragment as it
    /// arrives and returns the full accumulated text. Throws LLMError on failure.
    static func stream(provider: LLMProviderConfig?, systemPrompt: String,
                       messages: [LLMMessage], maxTokens: Int = 64000,
                       injectResponseLanguage: Bool = true,
                       onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let (p, system, turns) = try prepare(provider, systemPrompt: systemPrompt, messages: messages,
                                             injectResponseLanguage: injectResponseLanguage)
        switch p.type {
        case .claude: return try await streamClaude(p, system: system, messages: turns, maxTokens: maxTokens, onDelta: onDelta)
        case .openai, .custom: return try await streamOpenAI(p, system: system, messages: turns, onDelta: onDelta)
        case .gemini: return try await streamGemini(p, system: system, messages: turns, onDelta: onDelta)
        case .ollama: return try await streamOllama(p, system: system, messages: turns, onDelta: onDelta)
        }
    }

    // MARK: Shared preparation

    private static func prepare(_ provider: LLMProviderConfig?, systemPrompt: String,
                                messages: [LLMMessage],
                                injectResponseLanguage: Bool = true) throws -> (LLMProviderConfig, String, [LLMMessage]) {
        guard let provider else { throw LLMError.noProvider }
        guard !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider.type == .ollama else {
            throw LLMError.noAPIKey(provider.name)
        }
        let turns = normalizedHistory(messages)
        guard !turns.isEmpty else { throw LLMError.invalidResponse("empty message history") }

        let settings = SettingsManager.shared
        var fullPrompt = systemPrompt

        // Inject global tone/style rules
        let toneRules = settings.globalToneRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !toneRules.isEmpty {
            fullPrompt += "\n\nIMPORTANT STYLE RULES (always follow these):\n\(toneRules)"
        }

        // Response language — skipped for callers whose output language is
        // dictated by the task itself (e.g. free-mode edits/translations,
        // where this rule would fight the user's instruction)
        if injectResponseLanguage {
            let lang = settings.defaultResponseLanguage
            if lang == "auto" {
                fullPrompt += "\n\nIMPORTANT: Always answer in the same language as the user's input."
            } else {
                fullPrompt += "\n\nIMPORTANT: Always answer in \(lang)."
            }
        }

        return (provider, fullPrompt, turns)
    }

    /// APIs require the first turn to be from the user, and some reject empty or
    /// consecutive same-role messages: drop leading assistant turns and empties,
    /// merge consecutive same-role turns.
    static func normalizedHistory(_ messages: [LLMMessage]) -> [LLMMessage] {
        var result: [LLMMessage] = []
        for msg in messages {
            guard !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if result.isEmpty {
                if msg.role == .assistant { continue }
                result.append(msg)
            } else if result[result.count - 1].role == msg.role {
                result[result.count - 1] = LLMMessage(role: msg.role,
                                                      content: result[result.count - 1].content + "\n\n" + msg.content)
            } else {
                result.append(msg)
            }
        }
        return result
    }

    // MARK: HTTP helpers

    private static func jsonRequest(url: URL, body: [String: Any], streaming: Bool) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = streaming ? 300 : 120
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extract a human-readable message from an API error body.
    static func apiErrorMessage(fromBody data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let msg = error["message"] as? String { return msg }
            if let error = json["error"] as? String { return error } // Ollama style
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "no error details" : String(raw.prefix(300))
    }

    private static func wrapNetwork(_ error: Error, hint: String?) -> LLMError {
        if let llmError = error as? LLMError { return llmError }
        guard let hint else { return .network(error) }
        return .network(NSError(domain: "RaccoonTools.LLM", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "\(error.localizedDescription) \(hint)"
        ]))
    }

    private static func postJSON(_ req: URLRequest, networkHint: String? = nil) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw LLMError.invalidResponse("no HTTP response") }
            return (data, http)
        } catch {
            throw wrapNetwork(error, hint: networkHint)
        }
    }

    /// Open a streaming byte response; throws LLMError.api with the full body on non-200.
    private static func openByteStream(_ req: URLRequest, networkHint: String? = nil) async throws -> URLSession.AsyncBytes {
        let bytes: URLSession.AsyncBytes
        let resp: URLResponse
        do {
            (bytes, resp) = try await URLSession.shared.bytes(for: req)
        } catch {
            throw wrapNetwork(error, hint: networkHint)
        }
        guard let http = resp as? HTTPURLResponse else { throw LLMError.invalidResponse("no HTTP response") }
        if http.statusCode != 200 {
            var body = ""
            do {
                for try await line in bytes.lines { body += line + "\n" }
            } catch { /* report the status code with whatever body we got */ }
            throw LLMError.api(status: http.statusCode, message: apiErrorMessage(fromBody: Data(body.utf8)))
        }
        return bytes
    }

    // MARK: SSE parsing (pure helpers, unit-tested)

    /// Returns the payload of an SSE `data:` line, nil for other lines (events, comments, blanks).
    static func sseDataPayload(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        return String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseJSONObject(_ payload: String) -> [String: Any]? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Claude SSE event → (text delta, stream finished).
    static func claudeStreamEvent(_ payload: String) -> (text: String?, stop: Bool) {
        guard let json = parseJSONObject(payload), let type = json["type"] as? String else { return (nil, false) }
        if type == "message_stop" { return (nil, true) }
        guard type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else { return (nil, false) }
        return (text, false)
    }

    /// OpenAI-compatible SSE chunk → text delta (nil for role/finish chunks).
    static func openAIStreamDelta(_ payload: String) -> String? {
        guard let json = parseJSONObject(payload),
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let text = delta["content"] as? String else { return nil }
        return text
    }

    /// Gemini SSE chunk → text delta.
    static func geminiStreamDelta(_ payload: String) -> String? {
        guard let json = parseJSONObject(payload),
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else { return nil }
        return text
    }

    /// Ollama NDJSON line → (text delta, done).
    static func ollamaStreamChunk(_ line: String) -> (text: String?, done: Bool) {
        guard let json = parseJSONObject(line) else { return (nil, false) }
        let done = json["done"] as? Bool ?? false
        let text = (json["message"] as? [String: Any])?["content"] as? String
        return (text, done)
    }

    // MARK: - Claude

    private static func claudeRequest(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                      maxTokens: Int, streaming: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(p.baseURL)/v1/messages") else {
            throw LLMError.invalidResponse("invalid base URL: \(p.baseURL)")
        }
        var body: [String: Any] = [
            "model": p.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        if streaming { body["stream"] = true }
        var req = try jsonRequest(url: url, body: body, streaming: streaming)
        req.setValue(p.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return req
    }

    private static func callClaude(_ p: LLMProviderConfig, system: String, messages: [LLMMessage], maxTokens: Int) async throws -> String {
        let req = try claudeRequest(p, system: system, messages: messages, maxTokens: maxTokens, streaming: false)
        let (data, http) = try await postJSON(req)
        guard http.statusCode == 200 else {
            throw LLMError.api(status: http.statusCode, message: apiErrorMessage(fromBody: data))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw LLMError.invalidResponse("unexpected Claude response shape")
        }
        return text
    }

    private static func streamClaude(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                     maxTokens: Int, onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let req = try claudeRequest(p, system: system, messages: messages, maxTokens: maxTokens, streaming: true)
        let bytes = try await openByteStream(req)
        var full = ""
        do {
            for try await line in bytes.lines {
                guard let payload = sseDataPayload(line) else { continue }
                let event = claudeStreamEvent(payload)
                if let text = event.text {
                    full += text
                    onDelta(text)
                }
                if event.stop { break }
            }
        } catch {
            throw wrapNetwork(error, hint: nil)
        }
        return full
    }

    // MARK: - OpenAI / custom (OpenAI-compatible)

    private static func openAIRequest(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                      streaming: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(p.baseURL)/v1/chat/completions") else {
            throw LLMError.invalidResponse("invalid base URL: \(p.baseURL)")
        }
        var apiMessages: [[String: Any]] = [["role": "system", "content": system]]
        apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        var body: [String: Any] = [
            "model": p.model,
            "messages": apiMessages
        ]
        if streaming { body["stream"] = true }
        var req = try jsonRequest(url: url, body: body, streaming: streaming)
        req.setValue("Bearer \(p.apiKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private static func callOpenAI(_ p: LLMProviderConfig, system: String, messages: [LLMMessage]) async throws -> String {
        let req = try openAIRequest(p, system: system, messages: messages, streaming: false)
        let (data, http) = try await postJSON(req)
        guard http.statusCode == 200 else {
            throw LLMError.api(status: http.statusCode, message: apiErrorMessage(fromBody: data))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else {
            throw LLMError.invalidResponse("unexpected OpenAI response shape")
        }
        return text
    }

    private static func streamOpenAI(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                     onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let req = try openAIRequest(p, system: system, messages: messages, streaming: true)
        let bytes = try await openByteStream(req)
        var full = ""
        do {
            for try await line in bytes.lines {
                guard let payload = sseDataPayload(line) else { continue }
                if payload == "[DONE]" { break }
                if let text = openAIStreamDelta(payload) {
                    full += text
                    onDelta(text)
                }
            }
        } catch {
            throw wrapNetwork(error, hint: nil)
        }
        return full
    }

    // MARK: - Gemini

    /// Thinking-off configs tried in order, falling through on HTTP 400:
    /// Gemini 2.5 disables thinking via thinkingBudget, Gemini 3 rejects
    /// thinkingBudget and expects thinkingLevel, older models accept no
    /// thinkingConfig at all. Model aliases (gemini-flash-latest) move
    /// across generations, so the accepted shape can't be known up front.
    static let geminiThinkingOffConfigs: [[String: Any]?] = [
        ["thinkingBudget": 0],
        ["thinkingLevel": "minimal"],
        nil,
    ]

    private static func geminiThinkingAttempts(_ p: LLMProviderConfig) -> [[String: Any]?] {
        p.enableThinking ? [nil] : geminiThinkingOffConfigs
    }

    private static func geminiRequest(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                      streaming: Bool, thinkingConfig: [String: Any]?) throws -> URLRequest {
        let apiKey = p.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize baseURL: strip trailing slash and /v1beta if user included it
        var baseURL = p.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseURL.hasSuffix("/") { baseURL = String(baseURL.dropLast()) }
        if baseURL.hasSuffix("/v1beta") { baseURL = String(baseURL.dropLast("/v1beta".count)) }
        let method = streaming ? "streamGenerateContent" : "generateContent"
        let path = "/v1beta/models/\(p.model):\(method)"
        guard var components = URLComponents(string: baseURL + path) else {
            throw LLMError.invalidResponse("invalid base URL: \(p.baseURL)")
        }
        var queryItems: [URLQueryItem] = []
        if streaming { queryItems.append(URLQueryItem(name: "alt", value: "sse")) }
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
        components.queryItems = queryItems
        guard let url = components.url else {
            throw LLMError.invalidResponse("invalid base URL: \(p.baseURL)")
        }

        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": messages.map {
                ["role": $0.role == .assistant ? "model" : "user", "parts": [["text": $0.content]]]
            },
        ]
        if let thinkingConfig {
            body["generationConfig"] = ["thinkingConfig": thinkingConfig]
        }
        return try jsonRequest(url: url, body: body, streaming: streaming)
    }

    private static func callGemini(_ p: LLMProviderConfig, system: String, messages: [LLMMessage]) async throws -> String {
        let attempts = geminiThinkingAttempts(p)
        for (i, thinkingConfig) in attempts.enumerated() {
            let req = try geminiRequest(p, system: system, messages: messages,
                                        streaming: false, thinkingConfig: thinkingConfig)
            let (data, http) = try await postJSON(req)
            if http.statusCode == 400 && i < attempts.count - 1 { continue }
            guard http.statusCode == 200 else {
                throw LLMError.api(status: http.statusCode, message: apiErrorMessage(fromBody: data))
            }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                let raw = String(data: data, encoding: .utf8) ?? "unreadable"
                throw LLMError.invalidResponse("unexpected Gemini response shape — \(String(raw.prefix(200)))")
            }
            return text
        }
        throw LLMError.invalidResponse("no Gemini request attempted") // unreachable, attempts is never empty
    }

    private static func streamGemini(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                     onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        // openByteStream fails before any delta is emitted, so falling through
        // to the next thinking config never duplicates streamed text.
        let attempts = geminiThinkingAttempts(p)
        var stream: URLSession.AsyncBytes?
        for (i, thinkingConfig) in attempts.enumerated() {
            let req = try geminiRequest(p, system: system, messages: messages,
                                        streaming: true, thinkingConfig: thinkingConfig)
            do {
                stream = try await openByteStream(req)
                break
            } catch LLMError.api(let status, let message) {
                if status == 400 && i < attempts.count - 1 { continue }
                throw LLMError.api(status: status, message: message)
            }
        }
        guard let bytes = stream else {
            throw LLMError.invalidResponse("no Gemini request attempted") // unreachable, attempts is never empty
        }
        var full = ""
        do {
            for try await line in bytes.lines {
                guard let payload = sseDataPayload(line) else { continue }
                if let text = geminiStreamDelta(payload) {
                    full += text
                    onDelta(text)
                }
            }
        } catch {
            throw wrapNetwork(error, hint: nil)
        }
        return full
    }

    // MARK: - Ollama

    private static let ollamaHint = "Make sure Ollama is running (ollama serve)."

    private static func ollamaRequest(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                      streaming: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(p.baseURL)/api/chat") else {
            throw LLMError.invalidResponse("invalid base URL: \(p.baseURL)")
        }
        var apiMessages: [[String: Any]] = [["role": "system", "content": system]]
        apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": p.model,
            "messages": apiMessages,
            "stream": streaming
        ]
        return try jsonRequest(url: url, body: body, streaming: streaming)
    }

    private static func callOllama(_ p: LLMProviderConfig, system: String, messages: [LLMMessage]) async throws -> String {
        let req = try ollamaRequest(p, system: system, messages: messages, streaming: false)
        let (data, http) = try await postJSON(req, networkHint: ollamaHint)
        guard http.statusCode == 200 else {
            throw LLMError.api(status: http.statusCode,
                               message: "\(apiErrorMessage(fromBody: data)) \(ollamaHint)")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMError.invalidResponse("unexpected Ollama response shape")
        }
        return text
    }

    private static func streamOllama(_ p: LLMProviderConfig, system: String, messages: [LLMMessage],
                                     onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let req = try ollamaRequest(p, system: system, messages: messages, streaming: true)
        let bytes = try await openByteStream(req, networkHint: ollamaHint)
        var full = ""
        do {
            for try await line in bytes.lines {
                let chunk = ollamaStreamChunk(line)
                if let text = chunk.text {
                    full += text
                    onDelta(text)
                }
                if chunk.done { break }
            }
        } catch {
            throw wrapNetwork(error, hint: ollamaHint)
        }
        return full
    }
}
