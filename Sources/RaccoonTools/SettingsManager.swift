import Foundation

/// A one-click action shown as a chip in contextual (free) mode.
/// `input` is submitted exactly as if the user had typed it: a tool name
/// runs that tool, anything else is sent to the AI as an instruction.
struct QuickAction: Codable, Hashable, Identifiable {
    var label: String
    var input: String
    var id: String { label + "|" + input }

    static let defaults: [QuickAction] = [
        QuickAction(label: "Fix", input: "fix grammar"),
        QuickAction(label: "Shorten", input: "make it shorter, keep the meaning"),
        QuickAction(label: "Rephrase", input: "rephrase this, keep the meaning and tone"),
        QuickAction(label: "Formal", input: "rephrase formal"),
        QuickAction(label: "Translate", input: "translate"),
    ]
}

/// A user-defined LLM tool: shows up in the launcher and contextual mode
/// exactly like a built-in one. The selected/typed/clipboard text is sent as
/// the user message with `prompt` as the system prompt.
struct CustomTool: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var path: String        // space-separated, e.g. "rephrase pirate"
    var description: String
    var prompt: String
}

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
    // Grammar/spelling engine for fix grammar / fix orth: "llm" or
    // "languagetool" (free public API, falls back to the LLM on error)
    @Published var grammarEngine: String {
        didSet { UserDefaults.standard.set(grammarEngine, forKey: "grammarEngine") }
    }
    // Dictionary engine for def: "llm" or "system" (offline macOS
    // dictionaries, falls back to the LLM when the word isn't found)
    @Published var dictionaryEngine: String {
        didSet { UserDefaults.standard.set(dictionaryEngine, forKey: "dictionaryEngine") }
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

    // Quick-action chips shown in contextual mode (Cmd+1…9)
    @Published var quickActions: [QuickAction] {
        didSet { saveCodable(quickActions, key: "quickActions") }
    }
    // The Cmd+1…9 shortcuts can collide with muscle memory (tab switching);
    // chips stay clickable when this is off
    @Published var quickActionShortcutsEnabled: Bool {
        didSet { UserDefaults.standard.set(quickActionShortcutsEnabled, forKey: "quickActionShortcutsEnabled") }
    }
    // Per-app tone rules: bundle identifier -> rule injected into the system
    // prompt when the contextual mode was invoked from that app
    @Published var appToneRules: [String: String] {
        didSet { saveCodable(appToneRules, key: "appToneRules") }
    }
    // Instant edit: second hotkey that applies a tool to the selection
    // without opening the panel
    @Published var instantEditEnabled: Bool {
        didSet { UserDefaults.standard.set(instantEditEnabled, forKey: "instantEditEnabled") }
    }
    @Published var instantEditToolPath: String {
        didSet { UserDefaults.standard.set(instantEditToolPath, forKey: "instantEditToolPath") }
    }
    @Published var instantEditKeyCode: Int {
        didSet { UserDefaults.standard.set(instantEditKeyCode, forKey: "instantEditKeyCode") }
    }
    @Published var instantEditModifiers: Int {
        didSet { UserDefaults.standard.set(instantEditModifiers, forKey: "instantEditModifiers") }
    }
    // First-launch onboarding
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    // Tool library: user-created tools and hidden built-ins
    @Published var customTools: [CustomTool] {
        didSet { saveCodable(customTools, key: "customTools") }
    }
    @Published var disabledToolPaths: Set<String> {
        didSet { saveCodable(Array(disabledToolPaths), key: "disabledToolPaths") }
    }
    // Rename/move layer over built-in tools: bindingKey (original path) →
    // user-chosen path. Renaming a shared prefix moves whole folders.
    @Published var toolPathOverrides: [String: String] {
        didSet { saveCodable(toolPathOverrides, key: "toolPathOverrides") }
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
        self.grammarEngine = UserDefaults.standard.string(forKey: "grammarEngine") ?? "llm"
        self.dictionaryEngine = UserDefaults.standard.string(forKey: "dictionaryEngine") ?? "llm"
        self.defaultTranslateTarget = UserDefaults.standard.string(forKey: "defaultTranslateTarget") ?? "en"
        self.globalToneRules = UserDefaults.standard.string(forKey: "globalToneRules") ?? ""
        self.defaultResponseLanguage = UserDefaults.standard.string(forKey: "defaultResponseLanguage") ?? "auto"
        self.quickActions = Self.loadCodable([QuickAction].self, key: "quickActions") ?? QuickAction.defaults
        self.quickActionShortcutsEnabled = UserDefaults.standard.object(forKey: "quickActionShortcutsEnabled") as? Bool ?? true
        self.appToneRules = Self.loadCodable([String: String].self, key: "appToneRules") ?? [:]
        self.instantEditEnabled = UserDefaults.standard.object(forKey: "instantEditEnabled") as? Bool ?? false
        self.instantEditToolPath = UserDefaults.standard.string(forKey: "instantEditToolPath") ?? "fix orth"
        // Default: Option+Cmd+E (keycode 14), same modifier mask as the main hotkey default
        self.instantEditKeyCode = UserDefaults.standard.object(forKey: "instantEditKeyCode") as? Int ?? 14
        self.instantEditModifiers = UserDefaults.standard.object(forKey: "instantEditModifiers") as? Int ?? 0x0900
        self.hasCompletedOnboarding = UserDefaults.standard.object(forKey: "hasCompletedOnboarding") as? Bool ?? false
        self.customTools = Self.loadCodable([CustomTool].self, key: "customTools") ?? []
        self.disabledToolPaths = Set(Self.loadCodable([String].self, key: "disabledToolPaths") ?? [])
        self.toolPathOverrides = Self.loadCodable([String: String].self, key: "toolPathOverrides") ?? [:]

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDir = appSupport.appendingPathComponent("RaccoonTools")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Load providers
        var needsKeychainMigration = false
        let providersFile = configDir.appendingPathComponent("providers.json")
        if let data = try? Data(contentsOf: providersFile),
           var loaded = try? JSONDecoder().decode([LLMProviderConfig].self, from: data) {
            for i in loaded.indices {
                // Auto-migrate: if JSON still has a non-empty apiKey, move it to Keychain
                let jsonKey = loaded[i].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !jsonKey.isEmpty {
                    KeychainHelper.save(account: loaded[i].id, value: jsonKey)
                    loaded[i].apiKey = ""
                    needsKeychainMigration = true
                }
                // Restore API key from Keychain
                if let keychainKey = KeychainHelper.read(account: loaded[i].id) {
                    loaded[i].apiKey = keychainKey
                }
            }
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

        // Re-save JSON with keys stripped after all properties are initialized
        if needsKeychainMigration {
            saveProviders()
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
        // Save API keys to Keychain and write JSON with keys stripped
        var stripped = providers
        for i in stripped.indices {
            let key = stripped[i].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                KeychainHelper.save(account: stripped[i].id, value: key)
            }
            stripped[i].apiKey = ""
        }
        let file = configDir.appendingPathComponent("providers.json")
        try? JSONEncoder().encode(stripped).write(to: file)
    }

    private func saveToolBindings() {
        let file = configDir.appendingPathComponent("toolBindings.json")
        try? JSONEncoder().encode(toolBindings).write(to: file)
    }

    // MARK: - Codable settings in UserDefaults

    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
