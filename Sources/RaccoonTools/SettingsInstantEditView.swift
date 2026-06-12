import SwiftUI
import Carbon

/// Settings tab for the instant-edit hotkey: enable toggle, tool picker
/// (LLM text tools) and shortcut presets, mirroring the main hotkey UI.
struct InstantEditSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var registry = ToolRegistry.shared

    /// LLM tools that take a single text parameter (plus translate).
    var instantEditTools: [ToolCommand] {
        registry.tools
            .filter { ($0.usesLLM && $0.parameterName == "text") || $0.fullPath == "translate" }
            .sorted { $0.fullPath < $1.fullPath }
    }

    var body: some View {
        Form {
            Section("Instant Edit") {
                Toggle("Enable instant edit hotkey", isOn: $settings.instantEditEnabled)
                    .onChange(of: settings.instantEditEnabled) { _ in
                        NotificationCenter.default.post(name: .instantEditHotkeyChanged, object: nil)
                    }
                Text("Select text in any app and press the hotkey: the tool below runs on the selection and the result replaces it in place — no window shown, just a small status indicator.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Tool") {
                Picker("Run tool", selection: $settings.instantEditToolPath) {
                    ForEach(instantEditTools, id: \.fullPath) { tool in
                        Text("\(tool.fullPath) — \(tool.description)").tag(tool.fullPath)
                    }
                    if !instantEditTools.contains(where: { $0.fullPath == settings.instantEditToolPath }) {
                        Text(settings.instantEditToolPath).tag(settings.instantEditToolPath)
                    }
                }
                .disabled(!settings.instantEditEnabled)
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Instant edit")
                    Spacer()
                    ShortcutRecorderField(
                        keyCode: $settings.instantEditKeyCode,
                        modifiers: $settings.instantEditModifiers
                    ) {
                        NotificationCenter.default.post(name: .instantEditHotkeyChanged, object: nil)
                    }
                    .disabled(!settings.instantEditEnabled)
                }
                if settings.instantEditEnabled,
                   settings.hotKeyCode == settings.instantEditKeyCode,
                   settings.hotKeyModifiers == settings.instantEditModifiers {
                    Text("⚠︎ Same combination as the launcher shortcut — change one of them.")
                        .font(.caption).foregroundColor(.orange)
                }
                Text("Click the field, then press any combination you want (must include ⌘, ⌃ or ⌥). Applies immediately.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(20)
    }
}
