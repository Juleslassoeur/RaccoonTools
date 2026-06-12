import SwiftUI
import AppKit

// MARK: - Free view (contextual text assistant)

extension SpotlightView {
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
                    SelfSizingScrollView(maxHeight: 80) {
                        Text(state.freeOriginalText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Quick-action chips (hidden while a request is streaming)
            if !state.isRunning {
                FreeQuickActionChips { input in
                    submitFreeInput(input)
                }
                Divider()
            }

            // Tool suggestions while typing — in normal layout flow (not an
            // overlay) so up to 4 rows are ALWAYS visible below the input,
            // and the adaptive panel height accounts for them
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
                .padding(.vertical, 2)
                Divider()
            }

            // Chat messages
                ScrollViewReader { proxy in
                    SelfSizingScrollView(maxHeight: 300) {
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
                                    // Edit card (word diff + version navigator)
                                    FreeEditCardView(
                                        msg: msg,
                                        isLatestEdit: msg.id == state.freeMessages.last(where: { $0.source == "edit" })?.id,
                                        onApply: { text in
                                            // Don't apply while a response is still streaming
                                            guard !state.isRunning else { return }
                                            state.freeCurrentText = text
                                            applyFreeEdit()
                                        }
                                    )
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
                    .onChange(of: state.freeMessages.count) { _ in
                        withAnimation {
                            proxy.scrollTo("free-\(state.freeMessages.count)", anchor: .bottom)
                        }
                    }
                }

            // Action bar — always show Undo when there's history, Apply only when there's an unapplied edit
            let hasUnappliedEdit = state.freeMessages.contains { $0.source == "edit" && !state.appliedMessageIDs.contains($0.id) }
            if hasUnappliedEdit || state.freeHasApplied {
                Divider()
                HStack(spacing: 16) {
                    if hasUnappliedEdit {
                        HStack(spacing: 4) {
                            Image(systemName: state.freeTargetIsEditable ? "return" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(state.freeTargetIsEditable ? "Apply" : "Copy")
                                .font(.caption2.bold())
                        }
                        .foregroundColor(state.freeTargetIsEditable ? .green : .blue)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Don't apply while a response is still streaming
                            guard !state.isRunning else { return }
                            applyFreeEdit()
                        }
                    }

                    if state.freeTargetIsEditable {
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
                    }  // if freeTargetIsEditable (Undo is meaningless on read-only sources)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.04))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freeQuickAction)) { note in
            if let input = note.object as? String {
                submitFreeInput(input)
            }
        }
    }

    /// Submits `input` exactly as if the user had typed it and pressed Enter:
    /// a tool name runs the tool, anything else goes to the AI.
    func submitFreeInput(_ input: String) {
        guard !state.isRunning else { return }
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state.input = trimmed
        handleReturn()
    }

    func sendFreeMessage(_ message: String) {
        state.freeMessages.append(QAMessage(isUser: true, text: message, source: ""))
        state.isRunning = true

        let settings = SettingsManager.shared
        let toolPath = "free"
        var prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
        // Per-app tone rule: injected when the selection came from a configured app
        if let bundleID = state.previousApp?.bundleIdentifier,
           let rule = settings.appToneRules[bundleID]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rule.isEmpty {
            let appName = state.previousApp?.localizedName ?? bundleID
            prompt += "\n\nAPP-SPECIFIC STYLE RULE (the selected text comes from \(appName)):\n\(rule)"
        }
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
                let full = try await LLMService.stream(provider: provider, systemPrompt: prompt, messages: messages,
                                                       injectResponseLanguage: false) { delta in
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
                        // Version history: every successful EDIT becomes a new version
                        state.freeVersions.append(editedText)
                        state.freeVersionIndex = state.freeVersions.count - 1
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

    /// Copy a free-mode result to the clipboard (used when the source isn't
    /// editable). Intentional copy: the clipboard is NOT restored afterwards.
    func copyFreeResult(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.freeMessages.append(QAMessage(
            isUser: false,
            text: "Copied to clipboard — the source text isn't editable here.",
            source: "info"
        ))
    }

    func applyFreeEdit() {
        // Read-only source (PDF, web page, locked field…): replacing the
        // selection is impossible — copy the result instead.
        guard state.freeTargetIsEditable else {
            copyFreeResult(state.freeCurrentText)
            return
        }


        guard let prevApp = state.previousApp else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.freeCurrentText, forType: .string)
            return
        }

        let newText = state.freeCurrentText
        let panel = NSApp.windows.first { $0 is SpotlightPanel }

        // Put new text in clipboard for the synthetic Cmd+V, snapshotting the
        // user's clipboard first so it can be restored after the paste lands
        let clipboardSnapshot = PasteboardSnapshot.take()
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

                    // 5. Restore the user's clipboard (the paste has landed by
                    // now), re-select new text, show panel, take focus back
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        PasteboardSnapshot.restore(clipboardSnapshot)
                        HistoryManager.shared.ignoreCurrentChange()

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
}

// MARK: - Quick-action chips

/// Horizontal row of one-click action chips rendered in free mode.
/// The first 9 show their ⌘1…⌘9 keyboard hint.
struct FreeQuickActionChips: View {
    @ObservedObject var settings = SettingsManager.shared
    let onSubmit: (String) -> Void

    var body: some View {
        if !settings.quickActions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(settings.quickActions.enumerated()), id: \.offset) { index, action in
                        Button {
                            onSubmit(action.input)
                        } label: {
                            HStack(spacing: 4) {
                                Text(action.label)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                if index < 9 {
                                    Text("⌘\(index + 1)")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.08))
                            )
                            .overlay(
                                Capsule().stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
        }
    }
}

// MARK: - Edit card

/// Edit card in free mode: shows the edited text — as a word-level diff against
/// the original when the gating heuristics allow it — plus a version navigator
/// (‹ v2/3 ›) when several EDIT responses have accumulated.
struct FreeEditCardView: View {
    @ObservedObject var state = SpotlightState.shared
    let msg: QAMessage
    let isLatestEdit: Bool
    let onApply: (String) -> Void

    /// "Diff" / "Text" toggle on the card; diff is the default when gated in.
    @State private var showDiff = true
    /// Transient feedback after the Copy button is pressed.
    @State private var justCopied = false
    /// Manual touch-up of the AI's proposal before applying.
    @State private var isEditingManually = false
    @State private var manualDraft = ""

    /// Whether this card is driven by the version history: it must be the
    /// latest edit card AND correspond to the most recent version (tool
    /// results create edit cards without a version entry). While streaming,
    /// the live text always wins.
    private var isVersioned: Bool {
        isLatestEdit && !state.isRunning && msg.text == state.freeVersions.last
    }

    /// The text this card displays. The versioned (latest) card shows the
    /// selected version so ‹ › navigation changes what's shown (and applied);
    /// other cards keep their own text.
    private var displayedText: String {
        if isVersioned {
            let idx = min(max(state.freeVersionIndex, 0), state.freeVersions.count - 1)
            return state.freeVersions[idx]
        }
        return msg.text
    }

    /// Diff only makes sense for a partial rewording of a long-enough text,
    /// and never while the response is still streaming.
    private var diffEligible: Bool {
        !state.isRunning && DiffEngine.shouldShowDiff(original: state.freeOriginalText, edited: displayedText)
    }

    var body: some View {
        let isApplied = state.appliedMessageIDs.contains(msg.id)
        VStack(alignment: .leading, spacing: 6) {
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

                if isVersioned && state.freeVersions.count > 1 {
                    versionNavigator
                }

                Spacer()

                if diffEligible {
                    diffTextToggle
                }

                // Manual touch-up of the proposal before applying
                if isLatestEdit && !isApplied && !state.isRunning {
                    if isEditingManually {
                        Button {
                            isEditingManually = false
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark").font(.system(size: 8))
                                Text("Cancel").font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            commitManualEdit()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark").font(.system(size: 8))
                                Text("Done").font(.caption2)
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            manualDraft = displayedText
                            isEditingManually = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil").font(.system(size: 8))
                                Text("Edit").font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Copy is always available (and becomes the primary action
                // when the source text isn't editable)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayedText, forType: .string)
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc").font(.system(size: 8))
                        Text(justCopied ? "Copied" : "Copy").font(.caption2)
                    }
                    .foregroundColor(state.freeTargetIsEditable ? .secondary : .blue)
                }
                .buttonStyle(.plain)

                if !isApplied && state.freeTargetIsEditable {
                    Button {
                        onApply(displayedText)
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

            Group {
                if isEditingManually {
                    TextEditor(text: $manualDraft)
                        .font(.caption)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60, maxHeight: 180)
                } else if diffEligible && showDiff {
                    Text(diffAttributedString)
                } else {
                    Text(displayedText)
                }
            }
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

    // Compact "‹ v2/3 ›" navigator (also reachable via ⌘[ / ⌘])
    private var versionNavigator: some View {
        HStack(spacing: 3) {
            Button {
                FreeModeKeyHandler.navigateVersion(-1)
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(state.freeVersionIndex > 0 ? .accentColor : .secondary.opacity(0.4))
            .disabled(state.freeVersionIndex <= 0)

            Text("v\(min(state.freeVersionIndex, state.freeVersions.count - 1) + 1)/\(state.freeVersions.count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Button {
                FreeModeKeyHandler.navigateVersion(1)
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(state.freeVersionIndex < state.freeVersions.count - 1 ? .accentColor : .secondary.opacity(0.4))
            .disabled(state.freeVersionIndex >= state.freeVersions.count - 1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(3)
    }

    // Small "Diff" / "Text" toggle
    private var diffTextToggle: some View {
        HStack(spacing: 0) {
            toggleSegment("Diff", isActive: showDiff) { showDiff = true }
            toggleSegment("Text", isActive: !showDiff) { showDiff = false }
        }
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(3)
    }

    /// Registers the manual touch-up as a new version (so ‹ › navigation and
    /// Apply pick it up) and keeps the card's message in sync.
    private func commitManualEdit() {
        let newText = manualDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingManually = false
        guard !newText.isEmpty, newText != displayedText else { return }
        state.freeVersions.append(newText)
        state.freeVersionIndex = state.freeVersions.count - 1
        state.freeCurrentText = newText
        if let idx = state.freeMessages.firstIndex(where: { $0.id == msg.id }) {
            state.freeMessages[idx].text = newText
        }
    }

    private func toggleSegment(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? .accentColor : .secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    // Deletions in red strikethrough, insertions in green, unchanged in secondary
    private var diffAttributedString: AttributedString {
        let segments = DiffEngine.diff(original: state.freeOriginalText, edited: displayedText)
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { result += AttributedString(" ") }
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                piece.foregroundColor = .secondary
            case .inserted:
                piece.foregroundColor = .green
            case .deleted:
                piece.foregroundColor = .red
                piece.strikethroughStyle = .single
            }
            result += piece
        }
        return result
    }
}

// MARK: - Free-mode keyboard shortcuts

/// Handles free-mode-only shortcuts from the panel's key event monitor:
/// ⌘1…⌘9 submit the matching quick-action chip, ⌘[ / ⌘] navigate versions.
enum FreeModeKeyHandler {
    /// ANSI key codes for the digit row 1…9.
    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    /// Returns true when the event was consumed.
    static func handle(_ event: NSEvent) -> Bool {
        let state = SpotlightState.shared
        guard state.showFree else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == .command else { return false }

        // ⌘1…⌘9 → quick-action chip (disabled while streaming, like the chips)
        var digit = digitKeyCodes[event.keyCode]
        if digit == nil,
           let chars = event.charactersIgnoringModifiers,
           chars.count == 1, let d = Int(chars), (1...9).contains(d) {
            digit = d
        }
        if let d = digit {
            // Easy to hit by accident (tab-switching muscle memory) — let the
            // event through untouched when the shortcuts are disabled
            guard SettingsManager.shared.quickActionShortcutsEnabled else { return false }
            let actions = SettingsManager.shared.quickActions
            if !state.isRunning, d <= min(actions.count, 9) {
                NotificationCenter.default.post(name: .freeQuickAction, object: actions[d - 1].input)
            }
            return true
        }

        // ⌘[ / ⌘] → version history navigation
        if let chars = event.charactersIgnoringModifiers {
            if chars == "[" { navigateVersion(-1); return true }
            if chars == "]" { navigateVersion(1); return true }
        }
        return false
    }

    /// Moves the selected version; the latest edit card displays it and the
    /// existing Apply flow applies it (freeCurrentText tracks the selection).
    static func navigateVersion(_ delta: Int) {
        let state = SpotlightState.shared
        guard state.showFree, !state.isRunning, state.freeVersions.count > 1 else { return }
        let newIndex = min(max(state.freeVersionIndex + delta, 0), state.freeVersions.count - 1)
        guard newIndex != state.freeVersionIndex else { return }
        state.freeVersionIndex = newIndex
        state.freeCurrentText = state.freeVersions[newIndex]
    }
}

extension Notification.Name {
    /// Posted with the quick action's `input` string as the object; the free
    /// view submits it through the regular Enter path.
    static let freeQuickAction = Notification.Name("freeQuickAction")
}
