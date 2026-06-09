import SwiftUI
import Carbon

/// Settings tab for the instant-edit hotkey: enable toggle, tool picker
/// (LLM text tools) and shortcut presets, mirroring the main hotkey UI.
struct InstantEditSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var registry = ToolRegistry.shared
    @State private var selectedShortcut = 0

    static let shortcutPresets: [(String, UInt32, UInt32)] = [
        ("⌥⌘ E", UInt32(kVK_ANSI_E), UInt32(optionKey | cmdKey)),
        ("⌃⌘ E", UInt32(kVK_ANSI_E), UInt32(controlKey | cmdKey)),
        ("⌥⌘ I", UInt32(kVK_ANSI_I), UInt32(optionKey | cmdKey)),
        ("⌃⌥ F", UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey)),
    ]

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
                Picker("Instant edit", selection: $selectedShortcut) {
                    ForEach(0..<Self.shortcutPresets.count, id: \.self) { i in
                        Text(Self.shortcutPresets[i].0).tag(i)
                    }
                }
                .disabled(!settings.instantEditEnabled)
                .onChange(of: selectedShortcut) { idx in
                    let preset = Self.shortcutPresets[idx]
                    settings.instantEditKeyCode = Int(preset.1)
                    settings.instantEditModifiers = Int(preset.2)
                    NotificationCenter.default.post(name: .instantEditHotkeyChanged, object: nil)
                }
                Text("Current: \(KeyComboFormatter.string(keyCode: settings.instantEditKeyCode, modifiers: settings.instantEditModifiers))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(20)
        .onAppear {
            let code = UInt32(settings.instantEditKeyCode)
            let mods = UInt32(settings.instantEditModifiers)
            selectedShortcut = Self.shortcutPresets.firstIndex { $0.1 == code && $0.2 == mods } ?? 0
        }
    }
}
