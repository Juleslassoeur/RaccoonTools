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

            Section("Rename a folder / move tools") {
                Text("Renames a path prefix on every tool under it — e.g. \"get youtube\" → \"yt\" turns get youtube sound into yt sound. The tree IS the names: renaming prefixes restructures your folders.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("current prefix (e.g. get youtube)", text: $folderFrom)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                    TextField("new prefix (e.g. yt)", text: $folderTo)
                        .textFieldStyle(.roundedBorder)
                    Button("Rename") { renameFolder() }
                        .disabled(folderFrom.trimmingCharacters(in: .whitespaces).isEmpty
                                  || folderTo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Built-in tools") {
                Text("Edit a name to rename or move the tool (its provider/prompt settings follow it). Uncheck to hide it everywhere — nothing is deleted, re-check to bring it back. Renames need \"Apply changes\" (or a relaunch); hiding applies immediately.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(ToolRegistry.shared.builtinPaths, id: \.self) { original in
                    HStack(spacing: 8) {
                        Toggle("", isOn: enabledBinding(for: original))
                            .labelsHidden()
                        TextField(original, text: overrideBinding(for: original))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        if currentPath(for: original) != original {
                            Button {
                                settings.toolPathOverrides.removeValue(forKey: original)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to \"\(original)\"")
                        }
                    }
                }

                HStack {
                    if !settings.toolPathOverrides.isEmpty {
                        Button("Reset all names") { settings.toolPathOverrides = [:]; reloadAllTools() }
                    }
                    Spacer()
                    Button("Apply changes") { reloadAllTools() }
                }
            }
        }
        .formStyle(.grouped)
    }

    @State private var folderFrom = ""
    @State private var folderTo = ""

    /// The path a built-in is currently reachable under.
    private func currentPath(for original: String) -> String {
        settings.toolPathOverrides[original] ?? original
    }

    /// Prefix rename across built-ins (via overrides) and custom tools.
    private func renameFolder() {
        let from = folderFrom.trimmingCharacters(in: .whitespaces).lowercased()
        let to = folderTo.trimmingCharacters(in: .whitespaces).lowercased()
        guard !from.isEmpty, !to.isEmpty else { return }

        for original in ToolRegistry.shared.builtinPaths {
            let current = currentPath(for: original)
            if current == from || current.hasPrefix(from + " ") {
                let renamed = to + current.dropFirst(from.count)
                settings.toolPathOverrides[original] = renamed == original ? nil : renamed
            }
        }
        for index in settings.customTools.indices {
            let current = settings.customTools[index].path.lowercased()
            if current == from || current.hasPrefix(from + " ") {
                settings.customTools[index].path = to + current.dropFirst(from.count)
            }
        }
        folderFrom = ""
        folderTo = ""
        reloadAllTools()
    }

    /// Editable current path of a built-in; equal/empty values clear the override.
    private func overrideBinding(for original: String) -> Binding<String> {
        Binding(
            get: { currentPath(for: original) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed.isEmpty || trimmed == original {
                    settings.toolPathOverrides.removeValue(forKey: original)
                } else {
                    settings.toolPathOverrides[original] = trimmed
                }
            }
        )
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
