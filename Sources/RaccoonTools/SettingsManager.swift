import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // General
    @Published var outputFolder: String {
        didSet { UserDefaults.standard.set(outputFolder, forKey: "outputFolder") }
    }
    @Published var hotKeyModifiers: Int {
        didSet { UserDefaults.standard.set(hotKeyModifiers, forKey: "hotKeyModifiers") }
    }
    @Published var hotKeyCode: Int {
        didSet { UserDefaults.standard.set(hotKeyCode, forKey: "hotKeyCode") }
    }

    // Translate mode: "cli" (Google via translate-shell) or "llm"
    @Published var translateMode: String {
        didSet { UserDefaults.standard.set(translateMode, forKey: "translateMode") }
    }
    // Default target language for translate tool
    @Published var defaultTranslateTarget: String {
        didSet { UserDefaults.standard.set(defaultTranslateTarget, forKey: "defaultTranslateTarget") }
    }
    // Global tone/style rules injected into ALL LLM prompts
    @Published var globalToneRules: String {
        didSet { UserDefaults.standard.set(globalToneRules, forKey: "globalToneRules") }
    }
    // Default response language for free mode
    @Published var defaultResponseLanguage: String {
        didSet { UserDefaults.standard.set(defaultResponseLanguage, forKey: "defaultResponseLanguage") }
    }

    // LLM Providers
    @Published var providers: [LLMProviderConfig] {
        didSet { saveProviders() }
    }

    // Per-tool LLM bindings (toolPath -> binding)
    @Published var toolBindings: [String: ToolLLMBinding] {
        didSet { saveToolBindings() }
    }

    private let configDir: URL

    init() {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "~/Desktop"
        self.outputFolder = UserDefaults.standard.string(forKey: "outputFolder") ?? desktopPath
        self.hotKeyModifiers = UserDefaults.standard.object(forKey: "hotKeyModifiers") as? Int ?? 0x0900
        self.hotKeyCode = UserDefaults.standard.object(forKey: "hotKeyCode") as? Int ?? 49
        self.translateMode = UserDefaults.standard.string(forKey: "translateMode") ?? "cli"
        self.defaultTranslateTarget = UserDefaults.standard.string(forKey: "defaultTranslateTarget") ?? "en"
        self.globalToneRules = UserDefaults.standard.string(forKey: "globalToneRules") ?? ""
        self.defaultResponseLanguage = UserDefaults.standard.string(forKey: "defaultResponseLanguage") ?? "auto"

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDir = appSupport.appendingPathComponent("RaccoonTools")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Load providers
        let providersFile = configDir.appendingPathComponent("providers.json")
        if let data = try? Data(contentsOf: providersFile),
           let loaded = try? JSONDecoder().decode([LLMProviderConfig].self, from: data) {
            self.providers = loaded
        } else {
            self.providers = [.defaultClaude, .defaultOpenAI, .defaultGemini, .defaultOllama]
        }

        // Load tool bindings
        let bindingsFile = configDir.appendingPathComponent("toolBindings.json")
        if let data = try? Data(contentsOf: bindingsFile),
           let loaded = try? JSONDecoder().decode([String: ToolLLMBinding].self, from: data) {
            self.toolBindings = loaded
        } else {
            self.toolBindings = [:]
        }
    }

    func getProvider(for toolPath: String) -> LLMProviderConfig? {
        if let binding = toolBindings[toolPath],
           let provider = providers.first(where: { $0.id == binding.providerID }) {
            return provider
        }
        // Fallback: first provider with an API key, or ollama
        return providers.first(where: { !$0.apiKey.isEmpty }) ?? providers.first(where: { $0.type == .ollama })
    }

    func getSystemPrompt(for toolPath: String, default defaultPrompt: String) -> String {
        toolBindings[toolPath]?.systemPrompt ?? defaultPrompt
    }

    func setToolBinding(toolPath: String, providerID: String, systemPrompt: String) {
        toolBindings[toolPath] = ToolLLMBinding(providerID: providerID, systemPrompt: systemPrompt)
    }

    private func saveProviders() {
        let file = configDir.appendingPathComponent("providers.json")
        try? JSONEncoder().encode(providers).write(to: file)
    }

    private func saveToolBindings() {
        let file = configDir.appendingPathComponent("toolBindings.json")
        try? JSONEncoder().encode(toolBindings).write(to: file)
    }
}
