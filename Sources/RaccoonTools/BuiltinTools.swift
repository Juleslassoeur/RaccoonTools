import AppKit
import Foundation

// Registration order matters: ToolRegistry.search returns tools in
// registration order, which drives suggestion lists and ghost text.
func registerBuiltinTools() {
    let registry = ToolRegistry.shared
    let settings = SettingsManager.shared

    registerYouTubeTools(registry: registry, settings: settings)
    registerFileTools(registry: registry, settings: settings)
    registerSystemTools(registry: registry, settings: settings)
    registerTextTools(registry: registry, settings: settings)

    registry.markBuiltinsRegistered()
    registerCustomTools(registry: registry, settings: settings)
    registry.disabledPaths = settings.disabledToolPaths
}

/// User-defined LLM tools from Settings > Tool Library. They behave exactly
/// like built-in text tools: the selected/typed/clipboard text is the user
/// message, the tool's prompt is the system prompt, and per-tool provider
/// bindings (Tools tab) apply.
func registerCustomTools(registry: ToolRegistry, settings: SettingsManager) {
    let builtins = Set(registry.builtinPaths)
    var seen = Set<String>()

    for custom in settings.customTools {
        let tokens = registry.tokenize(custom.path.lowercased())
        guard !tokens.isEmpty else { continue }
        let fullPath = tokens.joined(separator: " ")
        // Collisions: built-ins win, and a duplicated custom path registers once
        guard !builtins.contains(fullPath), seen.insert(fullPath).inserted else { continue }

        let defaultPrompt = custom.prompt
        registry.register(ToolCommand(
            path: tokens,
            description: custom.description.isEmpty ? "Custom tool" : custom.description,
            parameterName: "text",
            usesLLM: true,
            handler: { input in
                var text = input.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
                guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
                let provider = settings.getProvider(for: fullPath)
                let prompt = settings.getSystemPrompt(for: fullPath, default: defaultPrompt)
                return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
            }
        ))
    }
}

/// Rebuilds the registry — call after the tool library (custom tools or
/// hidden built-ins) changes.
func reloadAllTools() {
    ToolRegistry.shared.removeAllTools()
    registerBuiltinTools()
}
