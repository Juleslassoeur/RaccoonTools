import SwiftUI
import AppKit

// Settings tab for the contextual (free) mode: quick-action chips and
// per-app tone rules.

struct FreeModeSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                quickActionsSection
                appToneRulesSection
            }
            .padding(20)
        }
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        GroupBox("Quick Actions") {
            VStack(alignment: .leading, spacing: 8) {
                Text("One-click chips shown in contextual mode. The input is submitted exactly as if you had typed it: a tool name runs the tool, anything else goes to the AI. The first 9 get ⌘1…⌘9 shortcuts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(settings.quickActions.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(index < 9 ? "⌘\(index + 1)" : "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 26, alignment: .trailing)
                        TextField("Label", text: Binding(
                            get: { index < settings.quickActions.count ? settings.quickActions[index].label : "" },
                            set: { if index < settings.quickActions.count { settings.quickActions[index].label = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        TextField("Instruction or tool (e.g. fix grammar)", text: Binding(
                            get: { index < settings.quickActions.count ? settings.quickActions[index].input : "" },
                            set: { if index < settings.quickActions.count { settings.quickActions[index].input = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button {
                            if index < settings.quickActions.count {
                                settings.quickActions.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this quick action")
                    }
                }

                HStack {
                    Button {
                        settings.quickActions.append(QuickAction(label: "New action", input: ""))
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Spacer()
                    Button("Restore defaults") {
                        settings.quickActions = QuickAction.defaults
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Per-app tone rules

    private var appToneRulesSection: some View {
        GroupBox("Per-App Tone Rules") {
            AppToneRulesEditor()
                .padding(8)
        }
    }
}

// MARK: - App tone rules editor

/// Editable list of bundle-id → style-rule rows. Rows are kept in a local
/// array (stable identity while typing) and synced back to settings.
struct AppToneRulesEditor: View {
    @ObservedObject var settings = SettingsManager.shared

    private struct RuleRow: Identifiable {
        let id = UUID()
        var bundleID: String
        var rule: String
    }

    @State private var rows: [RuleRow] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When the selected text comes from one of these apps, its style rule is added to the AI prompt.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField("com.apple.mail", text: $row.bundleID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        runningAppsMenu { app in
                            row.bundleID = app
                        }
                    }
                    .frame(width: 240)
                    TextField("Always professional and concise", text: $row.rule)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this rule")
                }
            }

            Button {
                rows.append(RuleRow(bundleID: "", rule: ""))
            } label: {
                Label("Add rule", systemImage: "plus")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rows = settings.appToneRules
                .sorted { $0.key < $1.key }
                .map { RuleRow(bundleID: $0.key, rule: $0.value) }
        }
        .onChange(of: rows.map { $0.bundleID + "\u{1}" + $0.rule }) { _ in
            syncToSettings()
        }
    }

    /// Dropdown of currently running regular apps for convenient bundle-id picking.
    private func runningAppsMenu(onPick: @escaping (String) -> Void) -> some View {
        Menu {
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app -> (name: String, bundleID: String)? in
                    guard let bundleID = app.bundleIdentifier else { return nil }
                    return (app.localizedName ?? bundleID, bundleID)
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if apps.isEmpty {
                Text("No running apps")
            }
            ForEach(apps, id: \.bundleID) { app in
                Button("\(app.name) — \(app.bundleID)") {
                    onPick(app.bundleID)
                }
            }
        } label: {
            Image(systemName: "app.badge")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .help("Pick from running apps")
    }

    private func syncToSettings() {
        var dict: [String: String] = [:]
        for row in rows {
            let key = row.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            dict[key] = row.rule
        }
        if dict != settings.appToneRules {
            settings.appToneRules = dict
        }
    }
}
