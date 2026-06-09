import SwiftUI
import AppKit

struct SpotlightView: View {
    @ObservedObject var state = SpotlightState.shared
    @ObservedObject var registry = ToolRegistry.shared
    @ObservedObject var history = HistoryManager.shared
    @State private var isDragOver = false
    // Frecency scores for suggestion ranking — computed once per input change, not per row

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
        // Report the natural content height so the panel can adapt (grows/shrinks)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SpotlightContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(SpotlightContentHeightKey.self) { height in
            NotificationCenter.default.post(
                name: .spotlightContentHeightChanged, object: nil,
                userInfo: ["height": height]
            )
        }
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
        .onAppear {
            state.suggestionScores = history.frecencyScores()
        }
        .onChange(of: state.input) { _ in
            state.suggestionScores = history.frecencyScores()
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

    /// Progress of the task currently shown in the running bar (nil → spinner only)
    var runningTaskProgress: Double? {
        state.runningTasks.last(where: { $0.toolName == state.runningToolName })?.progress
    }

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
            if let progress = runningTaskProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 140)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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
            let segments = registry.nextSegments(for: tokens, scores: state.suggestionScores)
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
                // Hug content when few rows so the panel can stay compact
                .frame(maxHeight: min(280, CGFloat(max(segments.count, 1)) * 34 + 8))
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
                // Hug content when few rows so the panel can stay compact
                .frame(maxHeight: min(280, CGFloat(max(suggestions.count, 1)) * 34 + 8))
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

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.resultText = "Copied to clipboard"
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
            let segments = registry.nextSegments(for: tokens, scores: state.suggestionScores)
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
            let segments = registry.nextSegments(for: tokens, scores: state.suggestionScores)
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

    // Internal (not private) so the free-mode extension can submit quick-action
    // chips through the exact same path as a typed Enter.
    func handleReturn() {
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
            let segments = registry.nextSegments(for: tokens, scores: state.suggestionScores)
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
            let segments = registry.nextSegments(for: tokens, scores: state.suggestionScores)
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
                    if tool.usesLLM { state.cacheLLMResult(result, for: cacheKey) }
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

            // Free-mode shortcuts: ⌘1…⌘9 quick actions, ⌘[ / ⌘] version history
            if FreeModeKeyHandler.handle(event) { return nil }

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
                let segments = registry.nextSegments(for: tokens, scores: SpotlightState.shared.suggestionScores)
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
            let segments = registry.nextSegments(for: tokens, scores: SpotlightState.shared.suggestionScores)
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
