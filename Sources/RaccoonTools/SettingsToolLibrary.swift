import SwiftUI

/// Settings > Tool Library: create/delete custom LLM tools and hide built-in
/// ones, to tailor the launcher's tool tree to your own workflow.
struct ToolLibraryTab: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Custom tools") {
                Text("Your own LLM tools — they show up in the launcher and contextual mode like any built-in. Multi-word names create folders (\"rephrase pirate\" lives under rephrase). Assign a specific provider per tool in the Tools tab.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($settings.customTools) { $tool in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("name (e.g. rephrase pirate)", text: $tool.path)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 210)
                            TextField("Description", text: $tool.description)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                settings.customTools.removeAll { $0.id == tool.id }
                                reloadAllTools()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        TextEditor(text: $tool.prompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 54)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))
                        if pathCollidesWithBuiltin(tool.path) {
                            Text("⚠︎ this name collides with a built-in tool — it won't be registered")
                                .font(.caption2).foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 3)
                }

                HStack {
                    Button {
                        settings.customTools.append(CustomTool(
                            path: "",
                            description: "",
                            prompt: "You are a writing assistant. <describe the transformation>. Return only the transformed text, no explanations."
                        ))
                    } label: {
                        Label("Add tool", systemImage: "plus")
                    }
                    Spacer()
                    Button("Apply changes") { reloadAllTools() }
                        .help("Re-registers the tool list now (otherwise applied on next launch)")
                }
            }

            Section("Built-in tools") {
                Text("Uncheck a tool to hide it everywhere (suggestions, search, instant edit, menu bar). Nothing is deleted — re-check to bring it back. Applies immediately.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(ToolRegistry.shared.builtinPaths, id: \.self) { path in
                    Toggle(path, isOn: enabledBinding(for: path))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func enabledBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledToolPaths.contains(path) },
            set: { enabled in
                if enabled {
                    settings.disabledToolPaths.remove(path)
                } else {
                    settings.disabledToolPaths.insert(path)
                }
                ToolRegistry.shared.disabledPaths = settings.disabledToolPaths
            }
        )
    }

    private func pathCollidesWithBuiltin(_ path: String) -> Bool {
        let tokens = ToolRegistry.shared.tokenize(path.lowercased())
        guard !tokens.isEmpty else { return false }
        return ToolRegistry.shared.builtinPaths.contains(tokens.joined(separator: " "))
    }
}
