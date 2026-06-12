import SwiftUI
import Carbon

struct SettingsView: View {
    @State private var section: SettingsSection = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case providers = "LLM Providers"
        case contextual = "Contextual"
        case tools = "Tools"
        case library = "Tool Library"
        case instantEdit = "Instant Edit"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gear"
            case .providers: return "brain"
            case .contextual: return "text.cursor"
            case .tools: return "wrench"
            case .library: return "square.grid.2x2"
            case .instantEdit: return "bolt"
            }
        }
    }

    // Sidebar layout: the tab bar overflowed once the sections multiplied
    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 185)

            Divider()

            Group {
                switch section {
                case .general: GeneralSettingsTab()
                case .providers: LLMProvidersTab()
                case .contextual: FreeModeSettingsTab()
                case .tools: ToolBindingsTab()
                case .library: ToolLibraryTab()
                case .instantEdit: InstantEditSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 860, height: 560)
    }
}

// MARK: - General tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Keyboard Shortcut") {
                HStack {
                    Text("Open Launcher")
                    Spacer()
                    ShortcutRecorderField(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    ) {
                        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                    }
                }
                if settings.instantEditEnabled,
                   settings.hotKeyCode == settings.instantEditKeyCode,
                   settings.hotKeyModifiers == settings.instantEditModifiers {
                    Text("⚠︎ Same combination as the Instant Edit shortcut — change one of them.")
                        .font(.caption).foregroundColor(.orange)
                }
                Text("Click the field, then press any combination you want (must include ⌘, ⌃ or ⌥). Applies immediately.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Grammar & spelling (fix grammar / fix orth)") {
                Picker("Engine", selection: $settings.grammarEngine) {
                    Text("LLM (configure in Tools tab)").tag("llm")
                    Text("LanguageTool — free API, no key, faster (falls back to LLM on error)").tag("languagetool")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Dictionary (def)") {
                Picker("Engine", selection: $settings.dictionaryEngine) {
                    Text("LLM (configure in Tools tab)").tag("llm")
                    Text("macOS dictionaries — offline, instant (falls back to LLM if not found)").tag("system")
                }
                .pickerStyle(.radioGroup)
                Text("The offline engine uses the dictionaries enabled in Dictionary.app (add French ones there if needed). Synonyms stay on the LLM — there is no decent offline thesaurus for French.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Translate") {
                Picker("Engine", selection: $settings.translateMode) {
                    Text("Google Translate (CLI)").tag("cli")
                    Text("LLM (configure in Tools tab)").tag("llm")
                }
                .pickerStyle(.radioGroup)

                Picker("Default target language", selection: $settings.defaultTranslateTarget) {
                    Text("English").tag("en")
                    Text("French").tag("fr")
                    Text("Spanish").tag("es")
                    Text("German").tag("de")
                    Text("Italian").tag("it")
                    Text("Portuguese").tag("pt")
                    Text("Dutch").tag("nl")
                    Text("Chinese").tag("zh")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Arabic").tag("ar")
                    Text("Russian").tag("ru")
                }
            }

            Section("Response Language") {
                Picker("LLM responds in", selection: $settings.defaultResponseLanguage) {
                    Text("Same as input (auto)").tag("auto")
                    Text("English").tag("English")
                    Text("French").tag("French")
                    Text("Spanish").tag("Spanish")
                    Text("German").tag("German")
                }
                Text("Applies to all LLM tools and free mode.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Tone & Style Rules") {
                TextEditor(text: $settings.globalToneRules)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 80)
                    .border(Color.secondary.opacity(0.2))
                Text("These rules are injected into every LLM prompt.\nEx: \"Never use Hey. Always be formal. Use French idioms.\"")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Output Folder") {
                HStack {
                    Text(settings.outputFolder.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.outputFolder = url.path
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Default base URLs

func defaultBaseURL(for type: LLMProviderType) -> String {
    switch type {
    case .claude: return "https://api.anthropic.com"
    case .openai: return "https://api.openai.com"
    case .gemini: return "https://generativelanguage.googleapis.com"
    case .ollama: return "http://localhost:11434"
    case .custom: return "https://"
    }
}

// MARK: - LLM Providers tab

struct LLMProvidersTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedProviderIndex: Int? = 0
    @State private var fetchedModels: [String] = []
    @State private var loadingModels = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var connectionError: String = ""

    enum ConnectionStatus { case unknown, testing, ok, error }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                List(selection: $selectedProviderIndex) {
                    ForEach(Array(settings.providers.enumerated()), id: \.element.id) { index, provider in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && provider.type != .ollama ? Color.orange : Color.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(provider.name).font(.system(.body))
                                Text(provider.type.displayName)
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .tag(index)
                    }
                }
                .frame(width: 180)

                Divider()
                HStack {
                    Button { addProvider() } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                    Button { removeProvider() } label: { Image(systemName: "minus") }.buttonStyle(.plain)
                        .disabled(selectedProviderIndex == nil)
                    Spacer()
                }
                .padding(8)
            }

            Divider()

            // Detail
            if let idx = selectedProviderIndex, idx < settings.providers.count {
                providerDetail(index: idx)
                    .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Image(systemName: "brain").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.4))
                    Text("Select a provider").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedProviderIndex) { newIdx in
            fetchedModels = []
            connectionStatus = .unknown
            connectionError = ""
            if let idx = newIdx, idx < settings.providers.count {
                loadProviderData(settings.providers[idx])
            }
        }
    }

    func providerDetail(index: Int) -> some View {
        let binding = Binding(
            get: { settings.providers[index] },
            set: { settings.providers[index] = $0 }
        )
        let providerType = binding.type.wrappedValue

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name & Type
                GroupBox("Provider") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Name").frame(width: 70, alignment: .trailing)
                            TextField("Provider name", text: binding.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Type").frame(width: 70, alignment: .trailing)
                            Picker("", selection: Binding(
                                get: { binding.type.wrappedValue },
                                set: { newType in
                                    binding.type.wrappedValue = newType
                                    // Auto-fill base URL when type changes
                                    binding.baseURL.wrappedValue = defaultBaseURL(for: newType)
                                    binding.model.wrappedValue = ""
                                    fetchedModels = []
                                    connectionStatus = .unknown
                                }
                            )) {
                                ForEach(LLMProviderType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(6)
                }

                // API Key (not for Ollama)
                if providerType != .ollama {
                    GroupBox("API Key") {
                        VStack(spacing: 8) {
                            HStack {
                                SecureField("Paste your API key", text: Binding(
                                    get: { binding.apiKey.wrappedValue },
                                    set: { newKey in
                                        binding.apiKey.wrappedValue = newKey
                                        // Auto-test when key changes
                                        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.count > 10 {
                                            // Ensure base URL is set
                                            if binding.baseURL.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                || binding.baseURL.wrappedValue == "https://" {
                                                binding.baseURL.wrappedValue = defaultBaseURL(for: providerType)
                                            }
                                            testAndFetch(binding.wrappedValue)
                                        }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)

                                // Status indicator
                                switch connectionStatus {
                                case .unknown:
                                    Circle().fill(Color.gray).frame(width: 12, height: 12)
                                case .testing:
                                    ProgressView().controlSize(.small)
                                case .ok:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                case .error:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }

                            if connectionStatus == .ok {
                                HStack {
                                    Image(systemName: "checkmark").foregroundColor(.green).font(.caption)
                                    Text("Connected").font(.caption).foregroundColor(.green)
                                }
                            } else if connectionStatus == .error {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle").foregroundColor(.red).font(.caption)
                                    Text(connectionError).font(.caption).foregroundColor(.red)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(6)
                    }
                }

                // Model
                GroupBox("Model") {
                    VStack(spacing: 10) {
                        if fetchedModels.isEmpty {
                            HStack {
                                TextField("Model name", text: binding.model)
                                    .textFieldStyle(.roundedBorder)
                                Button(loadingModels ? "Loading..." : "Fetch models") {
                                    loadProviderData(binding.wrappedValue)
                                }
                                .disabled(loadingModels)
                            }
                        } else {
                            HStack {
                                Picker("Model", selection: binding.model) {
                                    ForEach(fetchedModels, id: \.self) { m in
                                        Text(m).tag(m)
                                    }
                                }
                                .labelsHidden()
                                Button { loadProviderData(binding.wrappedValue) } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.plain)
                            }
                            Text("\(fetchedModels.count) models available")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }

                // Advanced
                GroupBox("Advanced") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Base URL").frame(width: 70, alignment: .trailing)
                            TextField(defaultBaseURL(for: providerType), text: binding.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Image(systemName: "info.circle").foregroundColor(.secondary).font(.caption)
                            Text("Default: \(defaultBaseURL(for: providerType))")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }

                        Divider()

                        HStack {
                            Toggle("Enable Thinking", isOn: binding.enableThinking)
                            Spacer()
                        }
                        HStack {
                            Image(systemName: "info.circle").foregroundColor(.secondary).font(.caption)
                            Text("Extended thinking (Gemini, Claude). Slower but more accurate for complex tasks.")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding(6)
                }
            }
            .padding(16)
        }
        .onAppear {
            // Ensure base URL is set
            if binding.baseURL.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || binding.baseURL.wrappedValue == "https://" {
                binding.baseURL.wrappedValue = defaultBaseURL(for: providerType)
            }
            loadProviderData(binding.wrappedValue)
        }
    }

    // MARK: - Test connection + fetch models

    func testAndFetch(_ provider: LLMProviderConfig) {
        connectionStatus = .testing
        connectionError = ""
        fetchedModels = []
        loadingModels = true

        Task {
            let result = await fetchModelsAsync(provider)
            await MainActor.run {
                loadingModels = false
                if let models = result.models {
                    fetchedModels = models.sorted()
                    connectionStatus = .ok
                    connectionError = ""
                } else {
                    fetchedModels = []
                    connectionStatus = .error
                    connectionError = result.error ?? "Connection failed"
                }
            }
        }
    }

    func loadProviderData(_ provider: LLMProviderConfig) {
        let key = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty && provider.type != .ollama {
            connectionStatus = .unknown
            return
        }
        testAndFetch(provider)
    }

    struct FetchResult {
        var models: [String]?
        var error: String?
    }

    func cleanBase(_ raw: String, strip: String? = nil) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        if let s = strip, url.hasSuffix(s) {
            url = String(url.dropLast(s.count))
            while url.hasSuffix("/") { url = String(url.dropLast()) }
        }
        return url
    }

    func fetchModelsAsync(_ p: LLMProviderConfig) async -> FetchResult {
        let apiKey = p.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = p.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultBaseURL(for: p.type)
            : p.baseURL

        do {
            switch p.type {
            case .ollama:
                let base = cleanBase(baseURL)
                guard let url = URL(string: "\(base)/api/tags") else { return FetchResult(error: "Invalid URL") }
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else {
                    return FetchResult(error: "Invalid response from Ollama")
                }
                let names = models.compactMap { $0["name"] as? String }
                return FetchResult(models: names)

            case .gemini:
                let base = cleanBase(baseURL, strip: "/v1beta")
                guard var components = URLComponents(string: "\(base)/v1beta/models") else {
                    return FetchResult(error: "Invalid URL")
                }
                components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                guard let url = components.url else { return FetchResult(error: "Invalid URL") }
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let err = json["error"] as? [String: Any],
                       let msg = err["message"] as? String {
                        return FetchResult(error: msg)
                    }
                    return FetchResult(error: "HTTP \(http.statusCode)")
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else {
                    return FetchResult(error: "Invalid response")
                }
                let names = models.compactMap { m -> String? in
                    guard let name = m["name"] as? String,
                          let methods = m["supportedGenerationMethods"] as? [String],
                          methods.contains("generateContent") else { return nil }
                    return name.replacingOccurrences(of: "models/", with: "")
                }
                return FetchResult(models: names)

            case .openai, .custom:
                let base = cleanBase(baseURL)
                guard let url = URL(string: "\(base)/v1/models") else { return FetchResult(error: "Invalid URL") }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let err = json["error"] as? [String: Any],
                       let msg = err["message"] as? String {
                        return FetchResult(error: msg)
                    }
                    return FetchResult(error: "HTTP \(http.statusCode)")
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["data"] as? [[String: Any]] else {
                    return FetchResult(error: "Invalid response")
                }
                let names = models.compactMap { $0["id"] as? String }
                return FetchResult(models: names)

            case .claude:
                // Anthropic has no list endpoint — test with a tiny request
                let base = cleanBase(baseURL)
                guard let url = URL(string: "\(base)/v1/messages") else { return FetchResult(error: "Invalid URL") }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                req.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": "claude-sonnet-4-6", "max_tokens": 1,
                    "messages": [["role": "user", "content": "hi"]]
                ])
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    if http.statusCode == 200 || http.statusCode == 400 {
                        // 400 = valid key but bad request, still means connected
                    } else if http.statusCode == 401 {
                        return FetchResult(error: "Invalid API key")
                    } else {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let err = json["error"] as? [String: Any],
                           let msg = err["message"] as? String {
                            return FetchResult(error: msg)
                        }
                    }
                }
                return FetchResult(models: [
                    "claude-opus-4-6",
                    "claude-sonnet-4-6",
                    "claude-haiku-4-5",
                ])
            }
        } catch {
            return FetchResult(error: error.localizedDescription)
        }
    }

    func addProvider() {
        let new = LLMProviderConfig(
            id: UUID().uuidString, name: "New Provider", type: .custom,
            apiKey: "", model: "", baseURL: "https://"
        )
        settings.providers.append(new)
        selectedProviderIndex = settings.providers.count - 1
    }

    func removeProvider() {
        if let idx = selectedProviderIndex, idx < settings.providers.count {
            settings.providers.remove(at: idx)
            selectedProviderIndex = settings.providers.isEmpty ? nil : max(0, idx - 1)
        }
    }
}

// MARK: - Tool bindings tab

struct ToolBindingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var registry = ToolRegistry.shared
    @State private var selectedToolPath: String?

    var llmTools: [ToolCommand] {
        registry.tools.filter(\.usesLLM).sorted { $0.fullPath < $1.fullPath }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedToolPath) {
                ForEach(llmTools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.fullPath)
                            .font(.system(.body, design: .monospaced))
                        Text(tool.description)
                            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    // Bindings are keyed by the tool's stable identity so they
                    // survive renames/moves done in the Tool Library
                    .tag(tool.bindingKey)
                }
            }
            .frame(width: 200)

            Divider()

            if let toolPath = selectedToolPath {
                toolDetail(toolPath: toolPath).frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "wrench").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.4))
                    Text("Select a tool to configure\nits LLM provider and system prompt")
                        .foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func toolDetail(toolPath: String) -> some View {
        let currentBinding = settings.toolBindings[toolPath]
        let providerID = currentBinding?.providerID ?? settings.providers.first?.id ?? ""
        let prompt = currentBinding?.systemPrompt ?? defaultPromptFor(toolPath)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("LLM Provider") {
                    Picker("", selection: Binding(
                        get: { providerID },
                        set: { newID in
                            settings.setToolBinding(toolPath: toolPath, providerID: newID,
                                                    systemPrompt: settings.toolBindings[toolPath]?.systemPrompt ?? prompt)
                        }
                    )) {
                        ForEach(settings.providers) { p in
                            HStack {
                                Circle()
                                    .fill(p.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && p.type != .ollama ? Color.orange : Color.green)
                                    .frame(width: 6, height: 6)
                                Text("\(p.name) (\(p.model.isEmpty ? "no model" : p.model))")
                            }
                            .tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .padding(6)
                }

                GroupBox("System Prompt") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: Binding(
                            get: { prompt },
                            set: { newPrompt in
                                settings.setToolBinding(toolPath: toolPath,
                                                        providerID: settings.toolBindings[toolPath]?.providerID ?? providerID,
                                                        systemPrompt: newPrompt)
                            }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 140)
                        .border(Color.secondary.opacity(0.2))

                        HStack {
                            Button("Reset to default") {
                                settings.toolBindings.removeValue(forKey: toolPath)
                            }
                            Spacer()
                            Text("\(prompt.count) chars").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }
            }
            .padding(16)
        }
    }

    func defaultPromptFor(_ toolPath: String) -> String {
        LLMToolPrompts.defaults[toolPath] ?? "You are a helpful assistant."
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}
