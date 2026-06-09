import SwiftUI
import AppKit

struct SpotlightView: View {
    @ObservedObject var state = SpotlightState.shared
    @ObservedObject var registry = ToolRegistry.shared
    @ObservedObject var history = HistoryManager.shared
    @State private var isDragOver = false

    var commandState: CommandState {
        CommandState(input: state.input, registry: registry)
    }

    var dynamicPlaceholder: String {
        if state.showFree {
            let hasUnappliedEdit = state.freeMessages.contains { $0.source == "edit" && !state.appliedMessageIDs.contains($0.id) }
            if hasUnappliedEdit {
                return "⏎ apply, or keep refining..."
            }
            return "Instruction or tool..."
        }
        if state.preGrabbedSelectedText != nil && !(state.preGrabbedSelectedText?.isEmpty ?? true) {
            return "Tool or instruction..."
        }
        return "Type a command..."
    }

    var ghostText: String? {
        guard !state.input.isEmpty else { return nil }
        return registry.autocompleteSuggestion(for: state.input)
    }

    /// Determine if we should show tree-level segments vs search results
    var isTreeNavigation: Bool {
        let tokens = registry.tokenize(state.input)
        // Tree nav when empty, or when all typed tokens are complete segment matches
        if tokens.isEmpty { return true }
        // If input ends with a space, user completed a segment — show next level
        if state.input.hasSuffix(" ") && registry.allTokensComplete(tokens) && commandState.matchedTool == nil {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            // Captured text indicator
            if let captured = state.preGrabbedSelectedText, !captured.isEmpty, !state.showFree {
                HStack(spacing: 6) {
                    Image(systemName: "text.cursor")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text(String(captured.prefix(60)) + (captured.count > 60 ? "..." : ""))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.05))
            }

            if state.isRunning {
                Divider()
                runningBar
            }

            if let result = state.resultText {
                Divider()
                resultBar(result)
            }

            Divider()

            if state.showFree {
                freeView  // suggestions are shown as overlay inside freeView
            } else if state.showPrompt {
                promptView
            } else if state.showChat {
                chatView
            } else if state.showQA {
                qaView
            } else if state.showHistoryDetail {
                historyDetailView
            } else if state.showStructuredResult {
                structuredResultView
            } else if state.showColorPicker {
                colorView
            } else if state.showHistory {
                historyView
            } else if state.resultText == nil && !state.isRunning {
                suggestionsArea
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 680)
        .frame(minHeight: 380)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    let path = url.path
                    let filename = url.lastPathComponent
                    // Store full path, display only filename
                    state.droppedFilePath = path
                    if state.input.hasSuffix(" ") || state.input.isEmpty {
                        state.input += filename
                    } else {
                        state.input += " " + filename
                    }
                }
            }
            return true
        }
        .overlay(
            isDragOver ? RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 3)
                .background(Color.accentColor.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            : nil
        )
        .onChange(of: state.input) { _ in
            state.selectedIndex = 0
            if state.resultText != nil { state.resultText = nil }
            if state.showStructuredResult { state.showStructuredResult = false }
            if state.showHistory && state.input != "history " && state.input != "history" {
                state.showHistory = false
            }
        }
    }

    // MARK: - Search bar

    var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 18))

            ZStack(alignment: .leading) {
                if let ghost = ghostText {
                    Text(ghost)
                        .font(.system(size: 18))
                        .foregroundColor(.gray.opacity(0.3))
                }
                CommandTextFieldWrapper(
                    text: $state.input,
                    placeholder: dynamicPlaceholder,
                    onTab: handleTab,
                    onReturn: handleReturn,
                    onEscape: handleEscape,
                    onArrowDown: {}, // handled by event monitor
                    onArrowUp: {},
                    onRightArrow: {},
                    onLeftArrow: {}
                )
                .frame(height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 52)
        .clipped()
    }

    // MARK: - Running bar

    var runningBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Running:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(state.runningToolName)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Spacer()
            Button {
                ProcessManager.shared.cancel()
                state.isRunning = false
                state.resultText = "\(state.runningToolName) — Cancelled"
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Cancel")
                        .font(.caption)
                }
                .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - Result bar

    func resultBar(_ result: String) -> some View {
        let isError = result.contains("Error") || result.contains("Cancelled") || result.contains("not found")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(isError ? .red : .green)
                Text(isError ? "Error" : "Done")
                    .font(.caption.bold())
                    .foregroundColor(isError ? .red : .green)
                Spacer()
                Text("Enter to copy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    state.resultText = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            let lineCount = result.components(separatedBy: "\n").count
            let needsScroll = lineCount > 8

            if needsScroll {
                ScrollView {
                    Text(result)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 250)
            } else {
                Text(result)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isError ? Color.red.opacity(0.05) : Color.green.opacity(0.05))
    }

    // MARK: - Suggestions area

    @ViewBuilder
    var suggestionsArea: some View {
        if isTreeNavigation {
            let tokens = registry.tokenize(state.input)
            let segments = registry.nextSegments(for: tokens)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
                            segmentRow(seg: seg, index: index)
                                .id("seg-\(index)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
                .onChange(of: state.selectedIndex) { idx in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("seg-\(idx)", anchor: .center)
                    }
                }
            }
        } else {
            let suggestions = commandState.suggestions
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if suggestions.isEmpty {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.secondary)
                                Text("No matching tool")
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                        } else {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, tool in
                                toolRow(tool: tool, index: index)
                                    .id("tool-\(index)")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
                .onChange(of: state.selectedIndex) { idx in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("tool-\(idx)", anchor: .center)
                    }
                }
            }
        }
    }

    func segmentRow(seg: SegmentSuggestion, index: Int) -> some View {
        let isSelected = index == state.selectedIndex
        return HStack {
            Image(systemName: seg.isLeaf ? "terminal" : "folder")
                .font(.caption)
                .foregroundColor(seg.isLeaf ? .accentColor : .orange)
                .frame(width: 20)

            Text(seg.segment)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)

            if seg.usesLLM {
                Text("LLM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.purple.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(3)
            }

            if !seg.isLeaf {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.4))
            }

            Spacer()

            Text(seg.description)
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            appendSegment(seg)
        }
    }

    func toolRow(tool: ToolCommand, index: Int) -> some View {
        let isSelected = index == state.selectedIndex
        return HStack {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundColor(.accentColor)
                .frame(width: 18)

            if tool.usesLLM {
                Text("LLM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.purple.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(3)
            }

            ForEach(Array(tool.path.enumerated()), id: \.offset) { pathIdx, segment in
                if pathIdx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.4))
                }
                Text(segment)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(pathIdx < commandState.tokens.count ? .primary : .secondary)
                    .fontWeight(pathIdx < commandState.tokens.count ? .semibold : .regular)
            }
            if let param = tool.parameterName {
                Text("[\(param)]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.4))
            }
            Spacer()
            Text(tool.description)
                .foregroundColor(.secondary)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            state.input = tool.fullPath + " "
        }
    }

    // MARK: - History view

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
                ScrollView {
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
                .frame(maxHeight: 300)
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

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.resultText = "Copied to clipboard"
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

    private func copyEntry(_ entry: ClipboardEntry) {
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
                    ScrollView {
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
                    .frame(maxHeight: 280)
                    .onChange(of: state.historyDetailSelectedIndex) { idx in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("hd-\(idx)", anchor: .center) }
                    }
                }
            } else {
                // Raw text
                ScrollView {
                    Text(state.historyDetailEntry?.result ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 280)
            }
        }
    }



    // MARK: - Free view (contextual text assistant)

    var freeView: some View {
        VStack(spacing: 0) {
            // Contextual header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "text.cursor")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    if let appName = state.previousApp?.localizedName {
                        Text(appName)
                            .font(.caption.bold())
                    }
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(String(state.freeOriginalText.prefix(50)) + (state.freeOriginalText.count > 50 ? "..." : ""))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if !state.freeOriginalText.isEmpty {
                        Button(state.freeShowOriginal ? "hide" : "original") {
                            state.freeShowOriginal.toggle()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }

                if state.freeShowOriginal {
                    ScrollView {
                        Text(state.freeOriginalText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 80)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Chat messages
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(state.freeMessages.enumerated()), id: \.element.id) { index, msg in
                                if msg.isUser {
                                    // User message bubble
                                    HStack {
                                        Spacer()
                                        Text(msg.text)
                                            .font(.caption)
                                            .padding(8)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(8)
                                            .frame(maxWidth: 400, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 12)
                                } else if msg.source == "edit" {
                                    // Edit card
                                    freeEditCard(msg: msg)
                                        .padding(.horizontal, 12)
                                } else {
                                    // Answer / info bubble
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            if msg.source == "answer" {
                                                Text("Answer")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.blue)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(3)
                                            }
                                            Text(msg.text)
                                                .font(.caption)
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .background(Color.secondary.opacity(0.08))
                                                .cornerRadius(8)
                                        }
                                        .frame(maxWidth: 450, alignment: .leading)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }

                            if state.isRunning {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking...").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.vertical, 8)
                        .id("free-\(state.freeMessages.count)")
                    }
                    .frame(maxHeight: 240)
                    .onChange(of: state.freeMessages.count) { _ in
                        withAnimation {
                            proxy.scrollTo("free-\(state.freeMessages.count)", anchor: .bottom)
                        }
                    }
                }

                // Compact tool suggestions overlay
                if !state.input.trimmingCharacters(in: .whitespaces).isEmpty && !commandState.suggestions.isEmpty && !state.isRunning {
                    VStack(spacing: 0) {
                        ForEach(Array(commandState.suggestions.prefix(4).enumerated()), id: \.element.id) { index, tool in
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 14)
                                if tool.usesLLM {
                                    Text("LLM")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.purple.opacity(0.7))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(2)
                                }
                                Text(tool.fullPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                Spacer()
                                Text(tool.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(index == state.selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.input = tool.fullPath + " "
                            }
                        }
                    }
                    .background(.ultraThickMaterial)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                }
            }

            // Action bar — always show Undo when there's history, Apply only when there's an unapplied edit
            let hasUnappliedEdit = state.freeMessages.contains { $0.source == "edit" && !state.appliedMessageIDs.contains($0.id) }
            if hasUnappliedEdit || state.freeHasApplied {
                Divider()
                HStack(spacing: 16) {
                    if hasUnappliedEdit {
                        HStack(spacing: 4) {
                            Image(systemName: "return")
                                .font(.system(size: 9))
                            Text("Apply")
                                .font(.caption2.bold())
                        }
                        .foregroundColor(.green)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Don't apply while a response is still streaming
                            guard !state.isRunning else { return }
                            applyFreeEdit()
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9))
                        Text("Undo")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.freeCurrentText = state.freeOriginalText
                        state.appliedMessageIDs = []
                        state.freeMessages.append(QAMessage(isUser: false, text: "Restored to original.", source: "undo"))
                        // applyFreeEdit will re-select the old text using freeLastAppliedText,
                        // paste the original, then set freeLastAppliedText = original.
                        // After that, reset tracking so next edit starts fresh.
                        applyFreeEdit()
                        // Reset tracking AFTER apply captures the values it needs
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            state.freeHasApplied = false
                            state.freeLastAppliedText = ""
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.04))
            }
        }
    }

    // Edit card for free mode
    func freeEditCard(msg: QAMessage) -> some View {
        let isApplied = state.appliedMessageIDs.contains(msg.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text("Applied")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.accentColor)
                    Text("Edit")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                Spacer()
                if !isApplied {
                    Button {
                        // Don't apply while a response is still streaming
                        guard !state.isRunning else { return }
                        state.freeCurrentText = msg.text
                        applyFreeEdit()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "return").font(.system(size: 8))
                            Text("Apply").font(.caption2)
                        }
                        .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(msg.text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(isApplied ? Color.green.opacity(0.04) : Color.accentColor.opacity(0.06))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isApplied ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15), lineWidth: 1)
                )
        }
        .padding(8)
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Streaming LLM helpers

    /// Convert a QA transcript into real LLM turns (skipping local notices/errors).
    private func llmHistory(_ transcript: [QAMessage], limit: Int) -> [LLMMessage] {
        transcript.suffix(limit)
            .filter { $0.source != "error" && $0.source != "undo" }
            .map { LLMMessage(role: $0.isUser ? .user : .assistant, content: $0.text) }
    }

    /// Append a placeholder assistant message to a transcript, stream deltas into it,
    /// and replace it with an error message if the request throws.
    /// onComplete receives the trimmed full text and the placeholder index.
    private func streamIntoTranscript(
        provider: LLMProviderConfig?,
        systemPrompt: String,
        messages: [LLMMessage],
        transcript: ReferenceWritableKeyPath<SpotlightState, [QAMessage]>,
        onComplete: ((String, Int) -> Void)? = nil
    ) {
        state.isRunning = true
        let placeholder = QAMessage(isUser: false, text: "", source: "")
        let placeholderID = placeholder.id
        state[keyPath: transcript].append(placeholder)
        let state = self.state

        Task {
            do {
                let full = try await LLMService.stream(provider: provider, systemPrompt: systemPrompt, messages: messages) { delta in
                    Task { @MainActor in
                        guard let idx = state[keyPath: transcript].lastIndex(where: { $0.id == placeholderID }) else { return }
                        state[keyPath: transcript][idx].text += delta
                    }
                }
                await MainActor.run {
                    state.isRunning = false
                    let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let idx = state[keyPath: transcript].lastIndex(where: { $0.id == placeholderID }) else { return }
                    state[keyPath: transcript][idx].text = trimmed
                    onComplete?(trimmed, idx)
                }
            } catch {
                await MainActor.run {
                    state.isRunning = false
                    guard let idx = state[keyPath: transcript].lastIndex(where: { $0.id == placeholderID }) else { return }
                    state[keyPath: transcript][idx].text = "Error: \(error.localizedDescription)"
                    state[keyPath: transcript][idx].source = "error"
                }
            }
        }
    }

    private func sendFreeMessage(_ message: String) {
        state.freeMessages.append(QAMessage(isUser: true, text: message, source: ""))
        state.isRunning = true

        let settings = SettingsManager.shared
        let toolPath = "free"
        let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
        let provider = settings.getProvider(for: toolPath)
        let currentText = state.freeCurrentText

        // Real multi-turn history; assistant turns keep their protocol prefix
        // and the latest user turn carries the current text
        var messages: [LLMMessage] = state.freeMessages.suffix(20)
            .filter { $0.source != "error" && $0.source != "undo" }
            .map { msg in
                guard !msg.isUser else { return LLMMessage(role: .user, content: msg.text) }
                let prefix = msg.source == "edit" ? "EDIT: " : (msg.source == "answer" ? "ANSWER: " : "")
                return LLMMessage(role: .assistant, content: prefix + msg.text)
            }
        if let lastIdx = messages.indices.last, messages[lastIdx].role == .user {
            messages[lastIdx] = LLMMessage(role: .user, content: "Current text:\n\(currentText)\n\n\(message)")
        }

        let placeholder = QAMessage(isUser: false, text: "", source: "")
        let placeholderID = placeholder.id
        state.freeMessages.append(placeholder)
        let state = self.state
        // Buffers deltas until EDIT vs ANSWER is decided, then streams the rest
        let decider = FreeReplyStreamDecider()

        Task {
            do {
                let full = try await LLMService.stream(provider: provider, systemPrompt: prompt, messages: messages) { delta in
                    Task { @MainActor in
                        guard let idx = state.freeMessages.lastIndex(where: { $0.id == placeholderID }) else { return }
                        guard let chunk = decider.ingest(delta) else { return }
                        if state.freeMessages[idx].source.isEmpty, let kind = decider.kind {
                            state.freeMessages[idx].source = (kind == .edit) ? "edit" : "answer"
                        }
                        state.freeMessages[idx].text += chunk
                    }
                }
                await MainActor.run {
                    state.isRunning = false
                    guard let idx = state.freeMessages.lastIndex(where: { $0.id == placeholderID }) else { return }
                    // Final authoritative parse of the complete response
                    switch FreeReplyParser.parse(full) {
                    case .edit(let editedText):
                        state.freeMessages[idx].text = editedText
                        state.freeMessages[idx].source = "edit"
                        // Only a successful EDIT response may reach the apply-to-document path
                        state.freeCurrentText = editedText
                    case .answer(let answer):
                        state.freeMessages[idx].text = answer
                        state.freeMessages[idx].source = "answer"
                    }
                }
            } catch {
                await MainActor.run {
                    state.isRunning = false
                    guard let idx = state.freeMessages.lastIndex(where: { $0.id == placeholderID }) else { return }
                    state.freeMessages[idx].text = "Error: \(error.localizedDescription)"
                    state.freeMessages[idx].source = "error"
                }
            }
        }
    }

    private func applyFreeEdit() {
        guard let prevApp = state.previousApp else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.freeCurrentText, forType: .string)
            return
        }

        let newText = state.freeCurrentText
        let panel = NSApp.windows.first { $0 is SpotlightPanel }

        // Put new text in clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)

        // 1. Resign key so panel doesn't capture Cmd+V (stays visible), activate previous app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            panel?.resignKey()
            prevApp.activate()

            // 2. Wait for focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {

                // Fresh AX reference
                let systemWide = AXUIElementCreateSystemWide()
                var focRef: CFTypeRef?
                let axElement: AXUIElement?
                if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
                   let focused = focRef {
                    axElement = (focused as! AXUIElement)
                } else {
                    axElement = state.preGrabbedFocusedElement
                }

                // 3. Re-select old text if not first apply
                if state.freeHasApplied, let element = axElement {
                    let oldLen = state.freeLastAppliedText.utf16.count
                    var selRange = CFRange(location: state.freeSelectionStart, length: oldLen)
                    if let rangeValue = AXValueCreate(.cfRange, &selRange) {
                        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
                    }
                }

                // 4. Cmd+V
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
                    down?.flags = .maskCommand
                    let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                    up?.flags = .maskCommand
                    down?.post(tap: .cghidEventTap)
                    up?.post(tap: .cghidEventTap)

                    // 5. Re-select new text, show panel, take focus back
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if let element = axElement {
                            var newRange = CFRange(location: state.freeSelectionStart, length: newText.utf16.count)
                            if let rangeValue = AXValueCreate(.cfRange, &newRange) {
                                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
                            }
                        }

                        state.freeHasApplied = true
                        state.freeLastAppliedText = newText

                        // Reclaim focus
                        panel?.makeKey()
                        NSApp.activate(ignoringOtherApps: true)

                        if let lastEditIdx = state.freeMessages.lastIndex(where: { $0.source == "edit" }) {
                            state.appliedMessageIDs.insert(state.freeMessages[lastEditIdx].id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prompt view (content + instruction + Q&A refinement)

    var promptView: some View {
        VStack(spacing: 0) {
            // Header with current step
            HStack {
                Image(systemName: "text.badge.plus")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("Prompt")
                    .font(.caption.bold())
                Spacer()
                Text(promptStepLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        // Show conversation history
                        ForEach(Array(state.promptMessages.enumerated()), id: \.element.id) { index, msg in
                            HStack(alignment: .top) {
                                if msg.isUser {
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        if !msg.source.isEmpty {
                                            Text(msg.source)
                                                .font(.caption2)
                                                .foregroundColor(.accentColor)
                                        }
                                        Text(msg.text)
                                            .font(.caption)
                                            .padding(8)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(8)
                                            .frame(maxWidth: 450, alignment: .trailing)
                                    }
                                } else {
                                    Text(msg.text)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(8)
                                        .frame(maxWidth: 450, alignment: .leading)
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 12)
                            .id("prompt-\(index)")
                        }

                        if state.isRunning {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Working...").font(.caption).foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 280)
                .onChange(of: state.promptMessages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("prompt-\(state.promptMessages.count - 1)", anchor: .bottom)
                    }
                }
            }
        }
    }

    var promptStepLabel: String {
        switch state.promptStep {
        case .content: return "Step 1: Paste content + Enter"
        case .instruction: return "Step 2: What to do with it? + Enter"
        case .qa: return "Refine or Enter empty to generate"
        case .result: return "Done — Enter to copy"
        }
    }

    private func handlePromptInput(_ text: String) {
        switch state.promptStep {
        case .content:
            var content = text
            if content.isEmpty { content = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !content.isEmpty else { return }
            state.promptContent = content
            let preview = content.count > 100 ? String(content.prefix(100)) + "..." : content
            state.promptMessages.append(QAMessage(isUser: true, text: preview, source: "Content"))
            state.promptStep = .instruction
            state.input = ""

        case .instruction:
            guard !text.isEmpty else { return }
            state.promptInstruction = text
            state.promptMessages.append(QAMessage(isUser: true, text: text, source: "Instruction"))
            state.input = ""

            // Ask LLM if it needs clarification or can proceed
            let settings = SettingsManager.shared
            let provider = settings.getProvider(for: "prompt")
            let sysPrompt = """
            The user gave you content and an instruction. Analyze if you have enough info to proceed.
            If the instruction is clear enough, respond with ONLY:
            READY: (then produce the final result directly)
            If you need clarification, ask ONE short question.
            """
            let userMsg = "Content (\(state.promptContent.count) chars):\n\(String(state.promptContent.prefix(4000)))\n\nInstruction: \(state.promptInstruction)"
            streamIntoTranscript(provider: provider, systemPrompt: sysPrompt,
                                 messages: [LLMMessage(role: .user, content: userMsg)],
                                 transcript: \.promptMessages) { trimmed, idx in
                if trimmed.uppercased().hasPrefix("READY:") {
                    // LLM produced the result directly
                    state.promptMessages[idx].text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                    state.promptStep = .result
                } else {
                    // LLM asks a question
                    state.promptStep = .qa
                }
            }

        case .qa:
            // Empty input = "go ahead, produce the result"
            let answer = text.isEmpty ? "Go ahead, produce the final result." : text
            if !text.isEmpty {
                state.promptMessages.append(QAMessage(isUser: true, text: answer, source: ""))
            }
            state.input = ""

            let settings = SettingsManager.shared
            let provider = settings.getProvider(for: "prompt")
            let sysPrompt = "You are processing content with user instructions. Based on the conversation, produce the final result. If you still need info, ask ONE question. Otherwise prefix with READY: and give the result."
                + "\n\nContent:\n\(String(state.promptContent.prefix(4000)))"
            // Real multi-turn history (the content preview stays out — full content is in the system prompt)
            var messages = state.promptMessages
                .filter { $0.source != "Content" && $0.source != "error" }
                .map { LLMMessage(role: $0.isUser ? .user : .assistant, content: $0.text) }
            if text.isEmpty {
                messages.append(LLMMessage(role: .user, content: answer))
            }
            streamIntoTranscript(provider: provider, systemPrompt: sysPrompt,
                                 messages: messages, transcript: \.promptMessages) { trimmed, idx in
                if trimmed.uppercased().hasPrefix("READY:") {
                    state.promptMessages[idx].text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                    state.promptStep = .result
                }
            }

        case .result:
            // Enter copies the last assistant message
            if let last = state.promptMessages.last, !last.isUser {
                copyToClipboard(last.text)
            }
        }
    }

    // MARK: - Chat view (free LLM chat)

    var chatView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("Chat")
                    .font(.caption.bold())
                Spacer()
                Text("Type + Enter")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(state.chatMessages.enumerated()), id: \.element.id) { index, msg in
                            HStack(alignment: .top, spacing: 0) {
                                if msg.isUser {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(8)
                                        .frame(maxWidth: 400, alignment: .trailing)
                                } else {
                                    Text(msg.text)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(8)
                                        .frame(maxWidth: 400, alignment: .leading)
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 12)
                            .id("chat-\(index)")
                        }

                        if state.isRunning {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Thinking...").font(.caption).foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .id("chat-loading")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 280)
                .onChange(of: state.chatMessages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("chat-\(state.chatMessages.count - 1)", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func sendChatMessage(_ message: String) {
        guard !message.isEmpty else { return }

        state.chatMessages.append(QAMessage(isUser: true, text: message, source: ""))

        let settings = SettingsManager.shared
        let provider = settings.getProvider(for: "chat")
        // Response-language rules are injected globally by LLMService
        let systemPrompt = settings.getSystemPrompt(for: "chat", default: "You are a helpful, concise assistant.")
        let messages = llmHistory(state.chatMessages, limit: 20)

        streamIntoTranscript(provider: provider, systemPrompt: systemPrompt,
                             messages: messages, transcript: \.chatMessages)
    }

    // MARK: - Q&A chat view

    var qaView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text((state.qaFilePath as NSString).lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                Spacer()
                Text("Type question + Enter")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(state.qaMessages.enumerated()), id: \.element.id) { index, msg in
                            HStack(alignment: .top, spacing: 0) {
                                if msg.isUser {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(8)
                                        .frame(maxWidth: 400, alignment: .trailing)
                                } else {
                                    Text(msg.text)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(8)
                                        .frame(maxWidth: 400, alignment: .leading)
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 12)
                            .id("qa-\(index)")
                        }

                        if state.isRunning {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Thinking...").font(.caption).foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .id("qa-loading")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 280)
                .onChange(of: state.qaMessages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("qa-\(state.qaMessages.count - 1)", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func askQAQuestion(_ question: String) {
        guard !question.isEmpty, !state.qaFileContent.isEmpty else { return }

        state.qaMessages.append(QAMessage(isUser: true, text: question, source: ""))

        let settings = SettingsManager.shared
        let toolPath = "file qa"
        let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
        let provider = settings.getProvider(for: toolPath)
        let truncated = truncateForLLM(state.qaFileContent)

        // File content lives in the system prompt; the transcript becomes real turns
        let systemPrompt = "\(prompt)\n\nFile: \((state.qaFilePath as NSString).lastPathComponent)\n\nContent:\n\(truncated)"
        let messages = llmHistory(state.qaMessages, limit: 10)

        streamIntoTranscript(provider: provider, systemPrompt: systemPrompt,
                             messages: messages, transcript: \.qaMessages)
    }

    // MARK: - Structured result view (multi-option tools)

    var structuredResultView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.runningToolName)
                    .font(.caption.bold())
                Spacer()
                Text("↑↓ navigate, Enter to copy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(state.structuredResults.enumerated()), id: \.element.id) { index, option in
                            let isSelected = index == state.resultSelectedIndex
                            HStack(spacing: 0) {
                                // Left: value
                                Text(option.value)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .frame(width: 180, alignment: .leading)

                                // Right: detail
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)

                                Spacer()

                                Button { copyToClipboard(option.value) } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                            .onTapGesture { copyToClipboard(option.value) }
                            .id("opt-\(index)")
                        }
                    }
                }
                .frame(maxHeight: 280)
                .onChange(of: state.resultSelectedIndex) { idx in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("opt-\(idx)", anchor: .center)
                    }
                }
            }
        }
    }

    // Tools that should display as structured multi-option results
    static let multiOptionTools: Set<String> = ["synonym", "word"]

    func parseStructuredResult(_ text: String) -> [ResultOption]? {
        // Try JSON first: [{"word":"...","def":"..."}]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Extract JSON array from response (LLM might wrap in ```json blocks)
        var jsonStr = trimmed
        if let start = trimmed.range(of: "["), let end = trimmed.range(of: "]", options: .backwards) {
            jsonStr = String(trimmed[start.lowerBound...end.lowerBound])
        }
        if let data = jsonStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let options = arr.compactMap { item -> ResultOption? in
                let word = (item["word"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let def = (item["def"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !word.isEmpty else { return nil }
                return ResultOption(value: word, detail: def)
            }
            if options.count >= 2 { return options }
        }

        // Fallback: **word** — definition
        var options: [ResultOption] = []
        for line in text.components(separatedBy: "\n") {
            let ln = line.trimmingCharacters(in: .whitespaces)
            guard ln.contains("**") else { continue }
            let stripped = ln.replacingOccurrences(of: "**", with: "§")
            let segments = stripped.components(separatedBy: "§")
            if segments.count >= 3 {
                let value = segments[1].trimmingCharacters(in: .whitespaces)
                var detail = segments[2...].joined(separator: "").trimmingCharacters(in: .whitespaces)
                if detail.hasPrefix("—") || detail.hasPrefix("–") {
                    detail = String(detail.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if !value.isEmpty && value.count > 1 {
                    options.append(ResultOption(value: value, detail: detail))
                }
            }
        }
        return options.count >= 2 ? options : nil
    }

    // MARK: - Unified Color tool (history left, palette right)

    var colorView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Color")
                    .font(.caption.bold())
                Spacer()
                Button("Pick color") {
                    launchColorPicker()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if state.pickedColors.isEmpty {
                Text("Press Enter to pick a color from screen")
                    .foregroundColor(.secondary)
                    .padding(20)
            } else {
                HStack(spacing: 0) {
                    // LEFT: history
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(state.pickedColors.enumerated()), id: \.element.id) { index, color in
                                    let isSelected = index == state.colorSelectedIndex
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(nsColor: NSColor(
                                                red: CGFloat(color.r) / 255,
                                                green: CGFloat(color.g) / 255,
                                                blue: CGFloat(color.b) / 255, alpha: 1)))
                                            .frame(width: 20, height: 20)
                                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(color.hex)
                                                .font(.system(.caption, design: .monospaced))
                                                .fontWeight(.medium)
                                            Text(color.cssRGB)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button { copyToClipboard(color.hex) } label: {
                                            Image(systemName: "doc.on.doc").font(.caption2).foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .cornerRadius(4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.colorSelectedIndex = index
                                        generatePalette(for: color)
                                    }
                                    .id("color-\(index)")
                                }
                            }
                        }
                        .frame(width: 220)
                        .frame(maxHeight: 280)
                        .onChange(of: state.colorSelectedIndex) { idx in
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("color-\(idx)", anchor: .center)
                            }
                            // Generate palette for selected color
                            if idx < state.pickedColors.count {
                                generatePalette(for: state.pickedColors[idx])
                            }
                        }
                    }

                    Divider()

                    // RIGHT: palette
                    VStack(spacing: 0) {
                        HStack {
                            Text("Palette")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            if state.isRunning {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if state.paletteColors.isEmpty && !state.isRunning {
                            Text("Select a color")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxHeight: .infinity)
                        } else {
                            ForEach(state.paletteColors) { pc in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(nsColor: pc.color))
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))

                                    Text(pc.hex)
                                        .font(.system(.caption, design: .monospaced))

                                    Text(pc.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Button { copyToClipboard(pc.hex) } label: {
                                        Image(systemName: "doc.on.doc").font(.caption2).foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture { copyToClipboard(pc.hex) }
                            }
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func launchColorPicker() {
        state.showColorPicker = true
        NotificationCenter.default.post(name: .hideSpotlightTemporary, object: nil)

        let sampler = NSColorSampler()
        sampler.show { selectedColor in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showSpotlight, object: nil)
                if let color = selectedColor {
                    let picked = PickedColor(nsColor: color)
                    state.pickedColors.insert(picked, at: 0)
                    if state.pickedColors.count > 30 {
                        state.pickedColors = Array(state.pickedColors.prefix(30))
                    }
                    state.colorSelectedIndex = 0
                    generatePalette(for: picked)
                }
            }
        }
    }

    private func generatePalette(for color: PickedColor) {
        let key = color.hex.uppercased()

        // Use cache if available
        if let cached = state.paletteCache[key] {
            state.paletteColors = cached
            return
        }

        state.paletteColors = []
        state.isRunning = true
        state.runningToolName = "color palette"

        Task {
            let settings = SettingsManager.shared
            let toolPath = "color palette"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            do {
                let result = try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: color.hex)
                await MainActor.run {
                    state.isRunning = false
                    let colors = parsePaletteColors(result, fallbackHex: color.hex)
                    state.paletteColors = colors
                    state.paletteCache[key] = colors
                }
            } catch {
                await MainActor.run { state.isRunning = false }
            }
        }
    }

    private func parsePaletteColors(_ text: String, fallbackHex: String) -> [PaletteColor] {
        var colors = [PaletteColor]()
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Try pipe format: #XXXXXX|Name|Role
            let parts = trimmed.components(separatedBy: "|")
            if parts.count >= 2 {
                let hex = parts[0].trimmingCharacters(in: .whitespaces)
                if hex.contains("#") {
                    colors.append(PaletteColor(
                        hex: hex, name: parts[1].trimmingCharacters(in: .whitespaces),
                        role: parts.count >= 3 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
                    ))
                    continue
                }
            }
            // Try dash format: #XXXXXX — Name — Role
            let dashParts = trimmed.components(separatedBy: " — ")
            if dashParts.count >= 2, dashParts[0].trimmingCharacters(in: .whitespaces).contains("#") {
                colors.append(PaletteColor(
                    hex: dashParts[0].trimmingCharacters(in: .whitespaces),
                    name: dashParts[1].trimmingCharacters(in: .whitespaces),
                    role: dashParts.count >= 3 ? dashParts[2].trimmingCharacters(in: .whitespaces) : ""
                ))
            }
        }
        return colors.isEmpty ? [PaletteColor(hex: fallbackHex, name: "Source", role: "Primary")] : colors
    }

    // MARK: - Key handlers

    private func handleTab() {
        if state.showHistory || state.showColorPicker { return }
        if let ghost = ghostText, !ghost.contains("[") {
            state.input = ghost + " "
            return
        }
        // In tree mode, select the segment
        if isTreeNavigation {
            let tokens = registry.tokenize(state.input)
            let segments = registry.nextSegments(for: tokens)
            if !segments.isEmpty {
                let idx = min(state.selectedIndex, segments.count - 1)
                appendSegment(segments[idx])
            }
            return
        }
        let suggestions = commandState.suggestions
        guard !suggestions.isEmpty else { return }
        let idx = min(state.selectedIndex, suggestions.count - 1)
        state.input = suggestions[idx].fullPath + " "
    }

    private func handleRightArrow() {
        if state.showHistory { return }

        // In tree mode: right arrow enters the selected folder
        if isTreeNavigation {
            let tokens = registry.tokenize(state.input)
            let segments = registry.nextSegments(for: tokens)
            if !segments.isEmpty {
                let idx = min(state.selectedIndex, segments.count - 1)
                let seg = segments[idx]
                if !seg.isLeaf {
                    appendSegment(seg)
                    return
                }
            }
        }

        // Otherwise accept ghost text
        if let ghost = ghostText, !ghost.contains("[") {
            state.input = ghost + " "
        }
    }

    private func handleLeftArrow() {
        // Go back one level: remove last token
        let tokens = registry.tokenize(state.input)
        if !tokens.isEmpty {
            let newInput = tokens.dropLast().joined(separator: " ")
            state.input = newInput.isEmpty ? "" : newInput + " "
            state.selectedIndex = 0
        }
    }

    private func handleReturn() {
        // Free mode: empty Enter = apply edit, non-empty falls through to tool matching
        if state.showFree {
            let msg = state.input.trimmingCharacters(in: .whitespaces)
            if msg.isEmpty {
                let hasUnappliedEdit = state.freeMessages.contains { $0.source == "edit" && !state.appliedMessageIDs.contains($0.id) }
                if hasUnappliedEdit && !state.isRunning {
                    applyFreeEdit()
                }
                return
            }
            // Non-empty: fall through to tool matching below
            // If no tool matches, the fallback at the end sends to LLM
        }

        // Prompt mode
        if state.showPrompt {
            handlePromptInput(state.input.trimmingCharacters(in: .whitespaces))
            return
        }

        // Chat mode: Enter sends message
        if state.showChat {
            let msg = state.input.trimmingCharacters(in: .whitespaces)
            if !msg.isEmpty {
                sendChatMessage(msg)
                state.input = ""
            }
            return
        }

        // Q&A mode: Enter sends the question
        if state.showQA {
            let question = state.input.trimmingCharacters(in: .whitespaces)
            if !question.isEmpty {
                askQAQuestion(question)
                state.input = ""
            }
            return
        }

        // History detail: Enter copies selected option
        if state.showHistoryDetail {
            if !state.historyDetailOptions.isEmpty {
                let idx = min(state.historyDetailSelectedIndex, state.historyDetailOptions.count - 1)
                copyToClipboard(state.historyDetailOptions[idx].value)
            } else if let entry = state.historyDetailEntry {
                copyToClipboard(entry.result)
            }
            return
        }

        // Result shown → Enter applies to document if text captured, otherwise copies
        if let result = state.resultText, !result.starts(with: "Copied"), !result.starts(with: "Applied") {
            if let captured = state.preGrabbedSelectedText, !captured.isEmpty,
               !result.contains("Error") && !result.contains("Saved to") && !result.contains("Cancelled") {
                if !state.freeHasApplied { state.freeOriginalText = captured }
                state.freeCurrentText = result
                applyFreeEdit()
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                state.resultText = "Copied to clipboard"
            }
            return
        }

        // Structured result: Enter applies to document if text captured, otherwise copies
        if state.showStructuredResult && !state.structuredResults.isEmpty {
            let idx = min(state.resultSelectedIndex, state.structuredResults.count - 1)
            let value = state.structuredResults[idx].value

            if let captured = state.preGrabbedSelectedText, !captured.isEmpty {
                if !state.freeHasApplied {
                    state.freeOriginalText = captured
                }
                state.freeCurrentText = value
                applyFreeEdit()
            } else {
                copyToClipboard(value)
            }
            return
        }

        // Color picker: Enter copies selected color hex
        if state.showColorPicker {
            if state.pickedColors.isEmpty {
                launchColorPicker()
            } else {
                let idx = min(state.colorSelectedIndex, state.pickedColors.count - 1)
                copyToClipboard(state.pickedColors[idx].hex)
            }
            return
        }

        // In history mode: copy selected entry
        if state.showHistory {
            if state.historyTab == .tools {
                let commands = Array(history.commandHistory.prefix(30))
                if !commands.isEmpty {
                    let idx = min(state.historySelectedIndex, commands.count - 1)
                    copyToClipboard(commands[idx].result)
                }
            } else {
                let entries = state.historyTab == .clipboard
                    ? Array(history.clipboardHistory.prefix(40))
                    : Array(history.clipboardHistory.filter(\.isImage).prefix(20))
                if !entries.isEmpty {
                    let idx = min(state.historySelectedIndex, entries.count - 1)
                    copyEntry(entries[idx])
                }
            }
            return
        }

        let cs = commandState

        // Tool fully matched → execute
        if let tool = cs.matchedTool {
            let param = cs.parameter
            let hasCaptured = (state.showFree && !state.freeCurrentText.isEmpty)
                || (state.preGrabbedSelectedText != nil && !state.preGrabbedSelectedText!.isEmpty)
            if !param.isEmpty || tool.parameterName == nil || hasCaptured {
                executeTool(tool, param: param)
                return
            }
            return
        }

        // In tree mode, select segment
        if isTreeNavigation {
            let tokens = registry.tokenize(state.input)
            let segments = registry.nextSegments(for: tokens)
            if !segments.isEmpty {
                let idx = min(state.selectedIndex, segments.count - 1)
                appendSegment(segments[idx])
            }
            return
        }

        // Search mode: autocomplete or execute directly
        let suggestions = cs.suggestions
        if !suggestions.isEmpty {
            let idx = min(state.selectedIndex, suggestions.count - 1)
            let tool = suggestions[idx]
            if tool.parameterName == nil {
                state.input = tool.fullPath + " "
                executeTool(tool, param: "")
            } else if state.preGrabbedSelectedText != nil && !state.preGrabbedSelectedText!.isEmpty {
                // Tool needs param + we have captured text → execute with captured text
                state.input = tool.fullPath + " "
                executeTool(tool, param: "")
            } else {
                state.input = tool.fullPath + " "
            }
            return
        }

        // No tool matched + captured text → free mode (LLM instruction)
        let instruction = state.input.trimmingCharacters(in: .whitespaces)
        if !instruction.isEmpty,
           let captured = state.preGrabbedSelectedText, !captured.isEmpty {
            if !state.showFree {
                state.freeOriginalText = captured
                state.freeCurrentText = captured
                state.freeMessages = []
                state.showFree = true
            }
            sendFreeMessage(instruction)
            state.input = ""
        }
    }

    private func handleArrowDown() {
        if state.showHistory {
            let entries = state.historyTab == .clipboard
                ? history.clipboardHistory.prefix(40)
                : history.clipboardHistory.filter(\.isImage).prefix(20)
            state.historySelectedIndex = min(state.historySelectedIndex + 1, entries.count - 1)
        } else if isTreeNavigation {
            let tokens = registry.tokenize(state.input)
            let segments = registry.nextSegments(for: tokens)
            state.selectedIndex = min(state.selectedIndex + 1, segments.count - 1)
        } else {
            state.selectedIndex = min(state.selectedIndex + 1, commandState.suggestions.count - 1)
        }
    }

    private func handleArrowUp() {
        if state.showHistory {
            state.historySelectedIndex = max(state.historySelectedIndex - 1, 0)
        } else {
            state.selectedIndex = max(state.selectedIndex - 1, 0)
        }
    }

    private func handleEscape() {
        if state.isRunning {
            ProcessManager.shared.cancel()
            state.isRunning = false
            state.resultText = "\(state.runningToolName) — Cancelled"
        } else if state.showFree {
            state.showFree = false
            state.input = ""
        } else if state.showPrompt {
            state.showPrompt = false
            state.input = ""
        } else if state.showChat {
            state.showChat = false
            state.input = ""
        } else if state.showQA {
            state.showQA = false
            state.input = ""
        } else if state.showHistoryDetail {
            state.showHistoryDetail = false
            // Return to history tools tab
            state.showHistory = true
            state.historyTab = .tools
        } else if state.showStructuredResult {
            state.showStructuredResult = false
            state.input = ""
        } else if state.showColorPicker {
            state.showColorPicker = false
            state.input = ""
        } else if state.showHistory {
            state.showHistory = false
            state.input = ""
        } else if state.resultText != nil {
            state.resultText = nil
            state.input = ""
        } else if !state.input.isEmpty {
            state.input = ""
        } else {
            NotificationCenter.default.post(name: .hideSpotlight, object: nil)
        }
    }

    private func appendSegment(_ seg: SegmentSuggestion) {
        // If it's a leaf tool with no parameter, execute directly
        if seg.isLeaf, let tool = seg.tool, tool.parameterName == nil {
            let tokens = registry.tokenize(state.input)
            var newTokens = tokens
            if let last = tokens.last, seg.segment.lowercased().hasPrefix(last.lowercased()) {
                newTokens[newTokens.count - 1] = seg.segment
            } else {
                newTokens.append(seg.segment)
            }
            state.input = newTokens.joined(separator: " ") + " "
            executeTool(tool, param: "")
            return
        }

        let tokens = registry.tokenize(state.input)
        var newTokens = tokens
        if let last = tokens.last, seg.segment.lowercased().hasPrefix(last.lowercased()) {
            newTokens[newTokens.count - 1] = seg.segment
        } else {
            newTokens.append(seg.segment)
        }
        state.input = newTokens.joined(separator: " ") + " "
        state.selectedIndex = 0
    }

    private func executeTool(_ tool: ToolCommand, param: String) {
        // Special: history
        if tool.fullPath == "history" {
            state.showHistory = true
            return
        }

        // Special: color picker
        if tool.fullPath == "color" {
            launchColorPicker()
            return
        }

        // Special: prompt
        if tool.fullPath == "prompt" {
            state.showPrompt = true
            state.promptStep = .content
            state.promptMessages = []
            state.promptContent = ""
            state.promptInstruction = ""
            state.input = ""
            return
        }

        // Special: chat
        if tool.fullPath == "chat" {
            state.showChat = true
            state.input = ""
            return
        }

        // Special: file Q&A
        if tool.fullPath == "file qa" {
            let filePath = state.droppedFilePath ?? param.trimmingCharacters(in: .whitespaces)
            let expanded = (filePath as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded),
                  let data = FileManager.default.contents(atPath: expanded),
                  let content = String(data: data, encoding: .utf8) else {
                state.resultText = "Error: drag & drop a file first"
                return
            }
            state.qaFilePath = expanded
            state.qaFileContent = content
            state.qaMessages = []
            state.showQA = true
            state.input = ""
            return
        }

        // Resolve the actual parameter: dropped file > free mode current text > captured text > typed param
        let actualParam: String
        if let droppedPath = state.droppedFilePath, !param.isEmpty {
            actualParam = droppedPath
        } else if param.isEmpty, tool.parameterName != nil,
                  state.showFree, !state.freeCurrentText.isEmpty {
            actualParam = state.freeCurrentText
        } else if param.isEmpty, tool.parameterName != nil,
                  let captured = state.preGrabbedSelectedText, !captured.isEmpty {
            actualParam = captured
        } else {
            actualParam = param
        }

        // Enter free mode proactively for tools with captured text
        let hasCapturedContext = (state.preGrabbedSelectedText != nil && !state.preGrabbedSelectedText!.isEmpty)
            || (state.showFree && !state.freeCurrentText.isEmpty)
        if !state.showFree && hasCapturedContext {
            let captured = state.preGrabbedSelectedText ?? ""
            state.freeOriginalText = captured
            state.freeCurrentText = captured
            state.freeMessages = []
            state.showFree = true
            state.input = ""
        }

        // Check LLM cache
        let cacheKey = "\(tool.fullPath):\(actualParam)"
        if let cached = state.llmCache[cacheKey] {
            handleToolResult(cached, tool: tool)
            return
        }

        let taskID = state.addRunningTask(tool.fullPath)
        state.isRunning = true
        state.runningToolName = tool.fullPath
        state.resultText = nil

        Task {
            do {
                let result = try await tool.handler(actualParam)
                await MainActor.run {
                    state.isRunning = false
                    state.removeRunningTask(taskID)
                    // Cache the result
                    if tool.usesLLM { state.llmCache[cacheKey] = result }
                    handleToolResult(result, tool: tool)
                }
            } catch {
                await MainActor.run {
                    state.isRunning = false
                    state.removeRunningTask(taskID)
                    state.resultText = "\(tool.fullPath) — Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleToolResult(_ result: String, tool: ToolCommand) {
        // Save to history
        history.addCommand(
            HistoryEntry(command: state.input, toolPath: tool.fullPath,
                         result: String(result.prefix(500)))
        )

        // Tool + captured text → redirect content results to free mode chat
        if let captured = state.preGrabbedSelectedText, !captured.isEmpty {
            let isContentResult = result != "Done" && !result.hasPrefix("Error")
                && !result.hasPrefix("Saved to") && !result.hasPrefix("Subtitles")
                && !result.hasPrefix("Transcription") && !result.hasPrefix("Opened")
                && !result.hasPrefix("Network:")
            guard isContentResult else {
                // Non-content result (file ops, etc.) → show normally
                let display = "\(tool.fullPath) — \(result)"
                state.resultText = display
                return
            }
            // Structured results (synonym, word) stay in structured view
            if Self.multiOptionTools.contains(tool.fullPath),
               let options = parseStructuredResult(result) {
                state.structuredResults = options
                state.resultSelectedIndex = 0
                state.runningToolName = tool.fullPath
                state.showStructuredResult = true
                state.resultText = nil
                return
            }

            // Enter free mode with the tool result
            if !state.showFree {
                state.freeOriginalText = captured
                state.freeCurrentText = captured
                state.freeMessages = []
            }
            state.showFree = true
            state.freeCurrentText = result
            state.freeMessages.append(QAMessage(isUser: false, text: result, source: "edit"))
            state.input = ""
            return
        }

        // Try structured parsing for multi-option tools
        if Self.multiOptionTools.contains(tool.fullPath),
           let options = parseStructuredResult(result) {
            state.structuredResults = options
            state.resultSelectedIndex = 0
            state.runningToolName = tool.fullPath
            state.showStructuredResult = true
            state.resultText = nil
            return
        }

        // Regular result
        let isContentResult = result != "Done" && !result.hasPrefix("Error")
            && !result.hasPrefix("Saved to") && !result.hasPrefix("Subtitles")
            && !result.hasPrefix("Transcription")
        state.resultText = isContentResult ? result : "\(tool.fullPath) — \(result)"
    }
}

// MARK: - NSTextField wrapper
// Uses NSEvent local monitor for arrow keys (most reliable)
// and delegate doCommandBy for Tab/Enter/Escape

struct CommandTextFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Type a command..."
    var onTab: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onRightArrow: () -> Void
    var onLeftArrow: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        context.coordinator.field = field

        // Clean up any previous monitor before creating a new one
        if let old = context.coordinator.eventMonitor {
            NSEvent.removeMonitor(old)
            context.coordinator.eventMonitor = nil
        }

        // Local event monitor: catches arrow keys reliably at the app level
        context.coordinator.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak field] event in
            guard let field, field.currentEditor() != nil else { return event }

            switch event.keyCode {
            case 125: // Down
                SpotlightKeyHandler.handleArrowDown()
                return nil
            case 126: // Up
                SpotlightKeyHandler.handleArrowUp()
                return nil
            case 124: // Right — always navigate tools
                SpotlightKeyHandler.handleRightArrow()
                return nil
            case 123: // Left — always go back up
                SpotlightKeyHandler.handleLeftArrow()
                return nil
            default: break
            }
            return event
        }

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
            if let editor = nsView.currentEditor() {
                editor.selectedRange = NSRange(location: text.count, length: 0)
            }
        }
        nsView.placeholderString = placeholder
        context.coordinator.onTab = onTab
        context.coordinator.onReturn = onReturn
        context.coordinator.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTab: onTab, onReturn: onReturn, onEscape: onEscape)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onTab: () -> Void
        var onReturn: () -> Void
        var onEscape: () -> Void
        weak var field: NSTextField?
        var eventMonitor: Any?

        init(text: Binding<String>, onTab: @escaping () -> Void,
             onReturn: @escaping () -> Void, onEscape: @escaping () -> Void) {
            _text = text
            self.onTab = onTab
            self.onReturn = onReturn
            self.onEscape = onEscape
        }

        deinit {
            if let m = eventMonitor { NSEvent.removeMonitor(m) }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertTab(_:)) { onTab(); return true }
            if sel == #selector(NSResponder.insertNewline(_:)) { onReturn(); return true }
            if sel == #selector(NSResponder.cancelOperation(_:)) { onEscape(); return true }
            // Arrows handled by event monitor
            if sel == #selector(NSResponder.moveDown(_:)) { return true }
            if sel == #selector(NSResponder.moveUp(_:)) { return true }
            return false
        }
    }
}

/// Static key handler that reads/writes SpotlightState directly — no stale closures
enum SpotlightKeyHandler {
    static func handleArrowDown() {
        let state = SpotlightState.shared
        let registry = ToolRegistry.shared

        if state.showPrompt || state.showChat || state.showQA || (state.showHistoryDetail && state.historyDetailOptions.isEmpty) { return }

        // In free mode: only allow arrow nav when tool suggestions are showing
        if state.showFree {
            let input = state.input.trimmingCharacters(in: .whitespaces)
            let cs = CommandState(input: state.input, registry: registry)
            if input.isEmpty || cs.suggestions.isEmpty { return }
        }

        if state.showHistoryDetail {
            state.historyDetailSelectedIndex = min(state.historyDetailSelectedIndex + 1, state.historyDetailOptions.count - 1)
            return
        }

        if state.showStructuredResult {
            state.resultSelectedIndex = min(state.resultSelectedIndex + 1, state.structuredResults.count - 1)
            return
        }

        if state.showColorPicker {
            state.colorSelectedIndex = min(state.colorSelectedIndex + 1, state.pickedColors.count - 1)
            return
        }

        if state.showHistory {
            let count: Int
            switch state.historyTab {
            case .clipboard: count = min(HistoryManager.shared.clipboardHistory.count, 40)
            case .images: count = min(HistoryManager.shared.clipboardHistory.filter(\.isImage).count, 20)
            case .tools: count = min(HistoryManager.shared.commandHistory.count, 30)
            }
            state.historySelectedIndex = min(state.historySelectedIndex + 1, count - 1)
        } else {
            let tokens = registry.tokenize(state.input)
            let isTree = tokens.isEmpty || (state.input.hasSuffix(" ") && registry.allTokensComplete(tokens)
                && registry.resolve(input: state.input) == nil)
            if isTree {
                let segments = registry.nextSegments(for: tokens)
                state.selectedIndex = min(state.selectedIndex + 1, segments.count - 1)
            } else {
                let cs = CommandState(input: state.input, registry: registry)
                state.selectedIndex = min(state.selectedIndex + 1, cs.suggestions.count - 1)
            }
        }
    }

    static func handleArrowUp() {
        let state = SpotlightState.shared
        if state.showHistoryDetail && !state.historyDetailOptions.isEmpty {
            state.historyDetailSelectedIndex = max(state.historyDetailSelectedIndex - 1, 0)
        } else if state.showStructuredResult {
            state.resultSelectedIndex = max(state.resultSelectedIndex - 1, 0)
        } else if state.showColorPicker {
            state.colorSelectedIndex = max(state.colorSelectedIndex - 1, 0)
        } else if state.showHistory {
            state.historySelectedIndex = max(state.historySelectedIndex - 1, 0)
        } else {
            state.selectedIndex = max(state.selectedIndex - 1, 0)
        }
    }

    static func handleRightArrow() {
        let state = SpotlightState.shared
        let registry = ToolRegistry.shared

        if state.showHistory {
            if state.historyTab == .tools {
                // → on tools tab: open detail view for selected entry
                let commands = Array(HistoryManager.shared.commandHistory.prefix(30))
                if !commands.isEmpty {
                    let idx = min(state.historySelectedIndex, commands.count - 1)
                    let entry = commands[idx]
                    state.historyDetailEntry = entry
                    state.historyDetailSelectedIndex = 0
                    // Try to parse structured result from the stored result
                    // Use the SpotlightView's parser (accessed via static)
                    state.historyDetailOptions = parseHistoryResult(entry.result)
                    state.showHistory = false
                    state.showHistoryDetail = true
                }
                return
            }
            switch state.historyTab {
            case .clipboard: state.historyTab = .images
            case .images: state.historyTab = .tools
            default: break
            }
            state.historySelectedIndex = 0
            return
        }

        let tokens = registry.tokenize(state.input)
        let isTree = tokens.isEmpty || (state.input.hasSuffix(" ") && registry.allTokensComplete(tokens)
            && registry.resolve(input: state.input) == nil)

        if isTree {
            let segments = registry.nextSegments(for: tokens)
            if !segments.isEmpty {
                let idx = min(state.selectedIndex, segments.count - 1)
                let seg = segments[idx]
                var newTokens = tokens
                newTokens.append(seg.segment)
                state.input = newTokens.joined(separator: " ") + " "
                state.selectedIndex = 0
                return
            }
        }

        // Search mode: → selects the highlighted suggestion (enters it)
        let cs = CommandState(input: state.input, registry: registry)
        if !cs.suggestions.isEmpty {
            let idx = min(state.selectedIndex, cs.suggestions.count - 1)
            state.input = cs.suggestions[idx].fullPath + " "
            state.selectedIndex = 0
            return
        }

        // Accept ghost text
        if let suggestion = registry.autocompleteSuggestion(for: state.input),
           !suggestion.contains("[") {
            state.input = suggestion + " "
        }
    }

    static func parseHistoryResult(_ text: String) -> [ResultOption] {
        // Try JSON
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var jsonStr = trimmed
        if let s = trimmed.range(of: "["), let e = trimmed.range(of: "]", options: .backwards) {
            jsonStr = String(trimmed[s.lowerBound...e.lowerBound])
        }
        if let data = jsonStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let opts = arr.compactMap { item -> ResultOption? in
                let word = (item["word"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let def = (item["def"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !word.isEmpty else { return nil }
                return ResultOption(value: word, detail: def)
            }
            if opts.count >= 2 { return opts }
        }
        // Fallback **word**
        var options: [ResultOption] = []
        for line in text.components(separatedBy: "\n") {
            let ln = line.trimmingCharacters(in: .whitespaces)
            guard ln.contains("**") else { continue }
            let stripped = ln.replacingOccurrences(of: "**", with: "§")
            let segments = stripped.components(separatedBy: "§")
            if segments.count >= 3 {
                let value = segments[1].trimmingCharacters(in: .whitespaces)
                var detail = segments[2...].joined(separator: "").trimmingCharacters(in: .whitespaces)
                if detail.hasPrefix("—") || detail.hasPrefix("–") { detail = String(detail.dropFirst()).trimmingCharacters(in: .whitespaces) }
                if !value.isEmpty && value.count > 1 { options.append(ResultOption(value: value, detail: detail)) }
            }
        }
        return options
    }

    static func handleLeftArrow() {
        let state = SpotlightState.shared
        let registry = ToolRegistry.shared

        // If in any tool view, exit it first
        if state.showFree {
            if state.input.trimmingCharacters(in: .whitespaces).isEmpty {
                state.showFree = false
                state.selectedIndex = 0
                return
            }
            // Non-empty input: fall through to normal left arrow (go back in tree)
        }

        if state.showPrompt {
            state.showPrompt = false
            state.input = ""
            state.selectedIndex = 0
            return
        }

        if state.showChat {
            state.showChat = false
            state.input = ""
            state.selectedIndex = 0
            return
        }

        if state.showQA {
            state.showQA = false
            state.input = ""
            state.selectedIndex = 0
            return
        }

        if state.showHistoryDetail {
            state.showHistoryDetail = false
            state.showHistory = true
            state.historyTab = .tools
            return
        }

        if state.showStructuredResult {
            state.showStructuredResult = false
            state.input = ""
            state.selectedIndex = 0
            return
        }

        if state.showColorPicker {
            state.showColorPicker = false
            state.input = ""
            state.selectedIndex = 0
            return
        }

        if state.showHistory {
            switch state.historyTab {
            case .tools: state.historyTab = .images; state.historySelectedIndex = 0; return
            case .images: state.historyTab = .clipboard; state.historySelectedIndex = 0; return
            case .clipboard:
                state.showHistory = false
                state.input = ""
                state.selectedIndex = 0
                return
            }
        }

        // If result is showing, dismiss it
        if state.resultText != nil {
            state.resultText = nil
            state.input = ""
            state.selectedIndex = 0
            return
        }

        // Remove last token — go back up one level
        let tokens = registry.tokenize(state.input)
        if !tokens.isEmpty {
            let newInput = tokens.dropLast().joined(separator: " ")
            state.input = newInput.isEmpty ? "" : newInput + " "
            state.selectedIndex = 0
        }
    }
}

extension Notification.Name {
    static let hideSpotlight = Notification.Name("hideSpotlight")
    static let hideSpotlightTemporary = Notification.Name("hideSpotlightTemporary")
}
