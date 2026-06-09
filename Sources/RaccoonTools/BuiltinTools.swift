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
}
