import SwiftUI
import AppKit

// MARK: - History view

extension SpotlightView {
    var historyView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                historyTabButton(title: "Clipboard", icon: "doc.on.clipboard", tab: .clipboard)
                historyTabButton(title: "Images", icon: "photo", tab: .images)
                historyTabButton(title: "Tools", icon: "terminal", tab: .tools)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Divider().padding(.top, 4)

            ScrollViewReader { proxy in
                SelfSizingScrollView(maxHeight: 300) {
                    VStack(spacing: 0) {
                        if state.historyTab == .tools {
                            let commands = Array(history.commandHistory.prefix(30))
                            if commands.isEmpty {
                                Text("No tool history yet")
                                    .foregroundColor(.secondary)
                                    .padding(20)
                            } else {
                                ForEach(Array(commands.enumerated()), id: \.element.id) { index, entry in
                                    toolHistoryRow(entry, index: index)
                                        .id(index)
                                }
                            }
                        } else {
                            let entries = state.historyTab == .clipboard
                                ? Array(history.clipboardHistory.prefix(40))
                                : Array(history.clipboardHistory.filter(\.isImage).prefix(20))

                            if entries.isEmpty {
                                Text(state.historyTab == .clipboard ? "No clipboard history yet" : "No image history yet")
                                    .foregroundColor(.secondary)
                                    .padding(20)
                            } else {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    clipboardRow(entry, index: index)
                                        .id(index)
                                }
                            }
                        }
                    }
                }
                .onChange(of: state.historySelectedIndex) { idx in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    func historyTabButton(title: String, icon: String, tab: SpotlightState.HistoryTab) -> some View {
        Button {
            state.historyTab = tab
            state.historySelectedIndex = 0
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(title).font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(state.historyTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    func clipboardRow(_ entry: ClipboardEntry, index: Int) -> some View {
        let isSelected = index == state.historySelectedIndex
        return HStack(spacing: 8) {
            if entry.isImage {
                // Show thumbnail
                if let img = history.loadImage(for: entry) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 60, maxHeight: 40)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "photo")
                        .frame(width: 60, height: 40)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(entry.content.prefix(150)))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                }
            }
            Spacer()
            if isSelected {
                Text("Enter to copy")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            copyEntry(entry)
        }
    }

    func toolHistoryRow(_ entry: HistoryEntry, index: Int) -> some View {
        let isSelected = index == state.historySelectedIndex
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.toolPath)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 140, alignment: .leading)

            Text(entry.result)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            if isSelected {
                Text("Enter to copy")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }

            Button { copyToClipboard(entry.result) } label: {
                Image(systemName: "doc.on.doc").font(.caption2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { copyToClipboard(entry.result) }
    }

    func copyEntry(_ entry: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        if entry.isImage, let img = history.loadImage(for: entry), let tiff = img.tiffRepresentation {
            NSPasteboard.general.setData(tiff, forType: .tiff)
        } else {
            NSPasteboard.general.setString(entry.content, forType: .string)
        }
        state.resultText = "Copied to clipboard"
    }

    // MARK: - History detail view (→ on a tool history entry)

    var historyDetailView: some View {
        VStack(spacing: 0) {
            HStack {
                if let entry = state.historyDetailEntry {
                    Text(entry.toolPath)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("← back")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if !state.historyDetailOptions.isEmpty {
                // Structured view
                ScrollViewReader { proxy in
                    SelfSizingScrollView(maxHeight: 280) {
                        VStack(spacing: 0) {
                            ForEach(Array(state.historyDetailOptions.enumerated()), id: \.element.id) { index, option in
                                let isSelected = index == state.historyDetailSelectedIndex
                                HStack(spacing: 0) {
                                    Text(option.value)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                        .frame(width: 180, alignment: .leading)
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    Spacer()
                                    Button { copyToClipboard(option.value) } label: {
                                        Image(systemName: "doc.on.doc").font(.caption2).foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                                .onTapGesture { copyToClipboard(option.value) }
                                .id("hd-\(index)")
                            }
                        }
                    }
                    .onChange(of: state.historyDetailSelectedIndex) { idx in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("hd-\(idx)", anchor: .center) }
                    }
                }
            } else {
                // Raw text
                SelfSizingScrollView(maxHeight: 280) {
                    Text(state.historyDetailEntry?.result ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
    }
}
