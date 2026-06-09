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

    func sendFreeMessage(_ message: String) {
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

    func applyFreeEdit() {
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
}
