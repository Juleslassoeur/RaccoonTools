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

class LLMService {
    static func call(provider: LLMProviderConfig?, systemPrompt: String, userMessage: String, maxTokens: Int = 8192) async throws -> String {
        guard let provider else {
            return "Error: No LLM provider configured for this tool.\nGo to Raccoon Tools > Settings > Tools to configure."
        }
        guard !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider.type == .ollama else {
            return "Error: No API key set for \(provider.name).\nGo to Settings > LLM Providers."
        }

        let settings = SettingsManager.shared
        var fullPrompt = systemPrompt

        // Inject global tone/style rules
        let toneRules = settings.globalToneRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !toneRules.isEmpty {
            fullPrompt += "\n\nIMPORTANT STYLE RULES (always follow these):\n\(toneRules)"
        }

        // Response language
        let lang = settings.defaultResponseLanguage
        if lang == "auto" {
            fullPrompt += "\n\nIMPORTANT: Always answer in the same language as the user's input."
        } else {
            fullPrompt += "\n\nIMPORTANT: Always answer in \(lang)."
        }

        switch provider.type {
        case .claude: return try await callClaude(provider, system: fullPrompt, message: userMessage, maxTokens: maxTokens)
        case .openai, .custom: return try await callOpenAI(provider, system: fullPrompt, message: userMessage)
        case .gemini: return try await callGemini(provider, system: fullPrompt, message: userMessage)
        case .ollama: return try await callOllama(provider, system: fullPrompt, message: userMessage)
        }
    }

    // MARK: - Claude

    private static func callClaude(_ p: LLMProviderConfig, system: String, message: String, maxTokens: Int) async throws -> String {
        let url = URL(string: "\(p.baseURL)/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(p.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 120 // long generations (summaries) can take a while

        let body: [String: Any] = [
            "model": p.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": message]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return "Error: no response" }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if http.statusCode == 200,
           let content = json?["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }
        if let error = json?["error"] as? [String: Any],
           let msg = error["message"] as? String {
            return "API Error (\(http.statusCode)): \(msg)"
        }
        return "Error: HTTP \(http.statusCode)"
    }

    // MARK: - OpenAI

    private static func callOpenAI(_ p: LLMProviderConfig, system: String, message: String) async throws -> String {
        let url = URL(string: "\(p.baseURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(p.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120

        let body: [String: Any] = [
            "model": p.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": message]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return "Error: no response" }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if http.statusCode == 200,
           let choices = json?["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let text = msg["content"] as? String {
            return text
        }
        if let error = json?["error"] as? [String: Any],
           let msg = error["message"] as? String {
            return "API Error (\(http.statusCode)): \(msg)"
        }
        return "Error: HTTP \(http.statusCode)"
    }

    // MARK: - Gemini

    private static func callGemini(_ p: LLMProviderConfig, system: String, message: String) async throws -> String {
        let apiKey = p.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize baseURL: strip trailing slash and /v1beta if user included it
        var baseURL = p.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseURL.hasSuffix("/") { baseURL = String(baseURL.dropLast()) }
        if baseURL.hasSuffix("/v1beta") { baseURL = String(baseURL.dropLast("/v1beta".count)) }
        let path = "/v1beta/models/\(p.model):generateContent"
        guard var components = URLComponents(string: baseURL + path) else {
            return "Error: invalid base URL"
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { return "Error: invalid URL" }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["parts": [["text": message]]]],
        ]
        if !p.enableThinking {
            body["generationConfig"] = ["thinkingConfig": ["thinkingBudget": 0]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return "Error: no response" }

        // Parse response safely
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "unreadable"
            return "Error: invalid response — \(String(raw.prefix(200)))"
        }

        if http.statusCode == 200,
           let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            return "API Error (\(http.statusCode)): \(msg)"
        }
        return "Error: HTTP \(http.statusCode)"
    }

    // MARK: - Ollama

    private static func callOllama(_ p: LLMProviderConfig, system: String, message: String) async throws -> String {
        let url = URL(string: "\(p.baseURL)/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120 // local models can be slow

        let body: [String: Any] = [
            "model": p.model,
            "system": system,
            "prompt": message,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return "Error: no response from Ollama. Is it running?" }

        if http.statusCode == 200 {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let response = json?["response"] as? String {
                return response
            }
        }
        return "Error: Ollama HTTP \(http.statusCode). Make sure Ollama is running (ollama serve)."
    }
}
