import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pure path operations (unit-testable)

/// The tool tree IS the names: every structural operation (rename a node,
/// drag a folder somewhere else) reduces to rewriting path prefixes.
enum ToolTreePaths {
    /// New path for an item when the node at `nodePath` becomes `newNodePath`.
    /// Returns nil when the item is not under that node.
    static func rewritten(itemPath: String, nodePath: String, newNodePath: String) -> String? {
        if itemPath == nodePath { return newNodePath }
        if itemPath.hasPrefix(nodePath + " ") {
            return newNodePath + itemPath.dropFirst(nodePath.count)
        }
        return nil
    }

    /// Guard against dropping a folder into itself or one of its descendants.
    static func isSelfOrDescendant(_ candidate: String, of nodePath: String) -> Bool {
        candidate == nodePath || candidate.hasPrefix(nodePath + " ")
    }

    /// Last segment of a path ("get youtube sound" → "sound").
    static func lastSegment(_ path: String) -> String {
        path.components(separatedBy: " ").last ?? path
    }

    /// Parent prefix of a path ("get youtube sound" → "get youtube", "" at root).
    static func parent(_ path: String) -> String {
        path.components(separatedBy: " ").dropLast().joined(separator: " ")
    }

    /// Normalizes a user-typed segment/path: lowercase, single spaces.
    static func normalized(_ raw: String) -> String {
        raw.lowercased().split(separator: " ").joined(separator: " ")
    }
}

// MARK: - Tree model

struct LibraryNode: Identifiable {
    let id: String              // current full path, e.g. "get youtube"
    let name: String            // last segment
    var children: [LibraryNode]?  // nil = tool, non-nil = folder
    let bindingKey: String?     // tools: stable identity
    let isCustomTool: Bool
    let customID: UUID?

    var isFolder: Bool { children != nil }
}

// MARK: - Tool Library tab

/// Settings > Tool Library: the tool tree as folders & tools. Double-click to
/// rename, drag a node onto a folder (or the root zone) to move it — a moved
/// folder takes all its tools along. Provider/prompt settings and the hidden
/// state follow each tool through renames (stable identity).
struct ToolLibraryTab: View {
    @ObservedObject var settings = SettingsManager.shared

    @State private var editingID: String?
    @State private var editingText = ""
    @State private var selectedCustomID: UUID?
    @State private var rootTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Double-click to rename a tool or a folder. Drag anything onto a folder (or the root zone) to move it — folders take their whole content along. The eye hides a tool everywhere; trash deletes a custom tool.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.top, 10)

            List(tree, children: \.children) { node in
                nodeRow(node)
            }
            .listStyle(.inset)

            // Root drop zone: move a node back to the top level
            HStack {
                Image(systemName: "arrow.up.to.line")
                Text("Drop here to move to the top level")
                    .font(.caption)
            }
            .foregroundColor(rootTargeted ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(rootTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .padding(.horizontal, 12)
            .onDrop(of: [.plainText], isTargeted: $rootTargeted) { providers in
                handleDrop(providers, intoFolder: "")
            }

            Divider()

            HStack {
                Button {
                    let tool = CustomTool(
                        path: uniqueNewToolPath(),
                        description: "My custom tool",
                        prompt: "You are a writing assistant. <describe the transformation>. Return only the transformed text, no explanations."
                    )
                    settings.customTools.append(tool)
                    selectedCustomID = tool.id
                    reloadAllTools()
                } label: {
                    Label("Add tool", systemImage: "plus")
                }
                Text("New tools are LLM prompts — rename and drag them into any folder.")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                if !settings.toolPathOverrides.isEmpty {
                    Button("Reset built-in names") {
                        settings.toolPathOverrides = [:]
                        reloadAllTools()
                    }
                }
            }
            .padding(.horizontal, 12)

            if !settings.deletedToolPaths.isEmpty {
                DisclosureGroup {
                    ForEach(settings.deletedToolPaths.sorted(), id: \.self) { key in
                        HStack {
                            Text(settings.toolPathOverrides[key] ?? key)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Restore") {
                                settings.deletedToolPaths.remove(key)
                                ToolRegistry.shared.disabledPaths = settings.disabledToolPaths.union(settings.deletedToolPaths)
                            }
                            .font(.caption)
                        }
                    }
                } label: {
                    Label("Deleted tools (\(settings.deletedToolPaths.count))", systemImage: "trash")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
            }

            if let customID = selectedCustomID,
               let index = settings.customTools.firstIndex(where: { $0.id == customID }) {
                customToolEditor(index: index)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: Rows

    @ViewBuilder
    private func nodeRow(_ node: LibraryNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: node.isFolder ? "folder" : "terminal")
                .font(.caption)
                .foregroundColor(node.isFolder ? .orange : .accentColor)
                .frame(width: 16)

            if editingID == node.id {
                TextField("", text: $editingText, onCommit: { commitRename(node) })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onExitCommand { editingID = nil }
            } else {
                Text(node.name)
                    .font(.system(.caption, design: .monospaced))
                if node.isCustomTool {
                    Text("custom")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.purple.opacity(0.8))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.purple.opacity(0.1)).cornerRadius(2)
                }
            }

            Spacer()

            if editingID != node.id {
                if !node.isFolder, let key = node.bindingKey {
                    let hidden = settings.disabledToolPaths.contains(key)
                    Button {
                        if hidden {
                            settings.disabledToolPaths.remove(key)
                        } else {
                            settings.disabledToolPaths.insert(key)
                        }
                        ToolRegistry.shared.disabledPaths = settings.disabledToolPaths.union(settings.deletedToolPaths)
                    } label: {
                        Image(systemName: hidden ? "eye.slash" : "eye")
                            .font(.caption2)
                            .foregroundColor(hidden ? .orange : .secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(hidden ? "Hidden — click to show" : "Click to hide everywhere")
                }
                // Prompt-based built-ins can be deleted (restorable from the
                // trash section below); functional built-ins only hide
                if !node.isFolder, !node.isCustomTool, let key = node.bindingKey,
                   ToolRegistry.shared.builtinLLMKeys.contains(key) {
                    Button {
                        settings.deletedToolPaths.insert(key)
                        ToolRegistry.shared.disabledPaths = settings.disabledToolPaths.union(settings.deletedToolPaths)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2).foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete (restorable from the trash section below)")
                }
                if node.isCustomTool, let customID = node.customID {
                    Button {
                        selectedCustomID = customID
                    } label: {
                        Image(systemName: "text.bubble")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit prompt & description")
                    Button {
                        settings.customTools.removeAll { $0.id == customID }
                        if selectedCustomID == customID { selectedCustomID = nil }
                        reloadAllTools()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2).foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(rowIsHidden(node) ? 0.45 : 1)
        .onTapGesture(count: 2) { startRename(node) }
        .onDrag { NSItemProvider(object: node.id as NSString) }
        .ifFolderDropTarget(node, isFolder: node.isFolder) { providers in
            handleDrop(providers, intoFolder: node.id)
        }
    }

    private func rowIsHidden(_ node: LibraryNode) -> Bool {
        guard let key = node.bindingKey else { return false }
        return settings.disabledToolPaths.contains(key)
    }

    // MARK: Custom tool editor

    @ViewBuilder
    private func customToolEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Prompt — \(settings.customTools[index].path)")
                    .font(.caption.bold())
                Spacer()
                Button("Close") { selectedCustomID = nil }
                    .font(.caption)
            }
            TextField("Description", text: Binding(
                get: { settings.customTools[index].description },
                set: { settings.customTools[index].description = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            TextEditor(text: Binding(
                get: { settings.customTools[index].prompt },
                set: { settings.customTools[index].prompt = $0 }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(height: 70)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))
            Text("Provider binding for this tool lives in the Tools tab. Prompt changes apply on next run.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .onDisappear { reloadAllTools() }
    }

    // MARK: Tree building

    /// Current effective (bindingKey, path, custom) list driving the tree.
    /// Deleted built-ins are not listed (they live in the trash section).
    private var libraryItems: [(key: String, path: String, customID: UUID?)] {
        let builtins = ToolRegistry.shared.builtinPaths
            .filter { !settings.deletedToolPaths.contains($0) }
            .map { original in
                (key: original, path: settings.toolPathOverrides[original] ?? original, customID: UUID?.none)
            }
        let customs = settings.customTools.compactMap { tool -> (key: String, path: String, customID: UUID?)? in
            let path = ToolTreePaths.normalized(tool.path)
            guard !path.isEmpty else { return nil }
            return (key: "custom:\(tool.id.uuidString)", path: path, customID: tool.id)
        }
        return builtins + customs
    }

    private var tree: [LibraryNode] {
        buildNodes(items: libraryItems.map { ($0.key, $0.path.components(separatedBy: " "), $0.customID) }, prefix: [])
    }

    private func buildNodes(items: [(key: String, tokens: [String], customID: UUID?)], prefix: [String]) -> [LibraryNode] {
        var folders: [String: [(key: String, tokens: [String], customID: UUID?)]] = [:]
        var leaves: [LibraryNode] = []

        for item in items {
            guard let head = item.tokens.first else { continue }
            if item.tokens.count == 1 {
                let fullPath = (prefix + [head]).joined(separator: " ")
                leaves.append(LibraryNode(
                    id: fullPath, name: head, children: nil,
                    bindingKey: item.key, isCustomTool: item.customID != nil, customID: item.customID
                ))
            } else {
                folders[head, default: []].append((item.key, Array(item.tokens.dropFirst()), item.customID))
            }
        }

        let folderNodes = folders.keys.sorted().map { name -> LibraryNode in
            let fullPath = (prefix + [name]).joined(separator: " ")
            return LibraryNode(
                id: fullPath, name: name,
                children: buildNodes(items: folders[name]!, prefix: prefix + [name]),
                bindingKey: nil, isCustomTool: false, customID: nil
            )
        }
        return folderNodes + leaves.sorted { $0.name < $1.name }
    }

    // MARK: Operations

    private func startRename(_ node: LibraryNode) {
        editingID = node.id
        editingText = node.name
    }

    private func commitRename(_ node: LibraryNode) {
        defer { editingID = nil }
        let newName = ToolTreePaths.normalized(editingText)
        guard !newName.isEmpty, newName != node.name else { return }
        let parent = ToolTreePaths.parent(node.id)
        let newPath = parent.isEmpty ? newName : parent + " " + newName
        applyRewrite(nodePath: node.id, newNodePath: newPath)
    }

    private func handleDrop(_ providers: [NSItemProvider], intoFolder folder: String) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let dragged = object as? String else { return }
            DispatchQueue.main.async {
                // No-op when dropping a node into itself/its own subtree or
                // into the folder it already lives in
                guard !ToolTreePaths.isSelfOrDescendant(folder, of: dragged),
                      ToolTreePaths.parent(dragged) != folder else { return }
                let name = ToolTreePaths.lastSegment(dragged)
                let newPath = folder.isEmpty ? name : folder + " " + name
                applyRewrite(nodePath: dragged, newNodePath: newPath)
            }
        }
        return true
    }

    /// Rewrites every item under `nodePath` (built-ins via overrides, customs
    /// via their stored path) and re-registers the tools.
    private func applyRewrite(nodePath: String, newNodePath: String) {
        for original in ToolRegistry.shared.builtinPaths {
            let current = settings.toolPathOverrides[original] ?? original
            if let updated = ToolTreePaths.rewritten(itemPath: current, nodePath: nodePath, newNodePath: newNodePath) {
                settings.toolPathOverrides[original] = (updated == original) ? nil : updated
            }
        }
        for index in settings.customTools.indices {
            let current = ToolTreePaths.normalized(settings.customTools[index].path)
            if let updated = ToolTreePaths.rewritten(itemPath: current, nodePath: nodePath, newNodePath: newNodePath) {
                settings.customTools[index].path = updated
            }
        }
        reloadAllTools()
    }

    private func uniqueNewToolPath() -> String {
        let existing = Set(libraryItems.map(\.path))
        if !existing.contains("new tool") { return "new tool" }
        var n = 2
        while existing.contains("new tool \(n)") { n += 1 }
        return "new tool \(n)"
    }
}

// MARK: - Conditional drop modifier

private extension View {
    /// Folders accept drops; tools don't.
    @ViewBuilder
    func ifFolderDropTarget(_ node: LibraryNode, isFolder: Bool,
                            action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        if isFolder {
            self.onDrop(of: [.plainText], isTargeted: nil, perform: action)
        } else {
            self
        }
    }
}
