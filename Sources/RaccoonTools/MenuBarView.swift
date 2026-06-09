import SwiftUI

struct MenuBarView: View {
    @ObservedObject var registry = ToolRegistry.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var state = SpotlightState.shared

    var body: some View {
        // Open launcher
        Button {
            SpotlightState.shared.reset()
            NotificationCenter.default.post(name: .showSpotlight, object: nil)
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Open Launcher")
                Spacer()
                Text("⌥⌘ Space")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .keyboardShortcut(.space, modifiers: [.command, .option])

        Divider()

        // Running tasks (if any)
        if !state.runningTasks.isEmpty {
            ForEach(state.runningTasks) { task in
                RunningTaskRow(task: task)
            }
            Divider()
        }

        // Tools grouped in tree
        let tree = registry.buildTree()
        ForEach(tree) { node in
            ToolTreeMenu(node: node)
        }

        Divider()

        // Clipboard history
        Button {
            SpotlightState.shared.prefill("history ")
            NotificationCenter.default.post(name: .showSpotlight, object: nil)
        } label: {
            Label("Clipboard History", systemImage: "doc.on.clipboard")
        }

        // Settings
        Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",")

        Divider()

        HStack {
            Image(systemName: "folder")
            Text(shortenPath(settings.outputFolder))
                .lineLimit(1)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Divider()

        Button("Quit Raccoon Tools") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func shortenPath(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

struct RunningTaskRow: View {
    let task: RunningTaskInfo

    var body: some View {
        Button {
            ProcessManager.shared.cancel(task.id)
            SpotlightState.shared.removeRunningTask(task.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("~ \(task.toolName)\(percentLabel)  [cancel]")
                if let progress = task.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }
        }
    }

    // Menu-style items may flatten custom views, so the percentage is also
    // part of the label text
    private var percentLabel: String {
        guard let progress = task.progress else { return "" }
        return "  \(Int(progress * 100))%"
    }
}

struct ToolTreeMenu: View {
    let node: ToolTreeNode

    var body: some View {
        if node.children.isEmpty {
            if let tool = node.tool {
                Button {
                    SpotlightState.shared.prefill(tool.fullPath + " ")
                    NotificationCenter.default.post(name: .showSpotlight, object: nil)
                } label: {
                    HStack {
                        Text(node.name)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if let param = tool.parameterName {
                            Text("[\(param)]")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(node.name)
            }
        } else {
            Menu {
                ForEach(node.children) { child in
                    ToolTreeMenu(node: child)
                }
            } label: {
                Text(node.name)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}

extension Notification.Name {
    static let showSpotlight = Notification.Name("showSpotlight")
    static let showSpotlightWith = Notification.Name("showSpotlightWith")
    static let openSettings = Notification.Name("openSettings")
}
