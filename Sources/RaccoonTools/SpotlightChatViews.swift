import SwiftUI
import AppKit

// MARK: - Streaming LLM helpers

extension SpotlightView {
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

    /// Assistant bubble shared by the prompt, chat and file-QA transcripts.
    /// Completed responses render as markdown; the message still being
    /// streamed (last one while running) stays plain text so we don't
    /// re-parse markdown on every token. Error messages stay plain too.
    @ViewBuilder
    func assistantBubble(_ msg: QAMessage, isLast: Bool, maxWidth: CGFloat) -> some View {
        Group {
            if msg.source == "error" {
                Text(msg.text)
                    .font(.caption)
                    .textSelection(.enabled)
            } else {
                MarkdownText(text: msg.text, isStreaming: state.isRunning && isLast)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .frame(maxWidth: maxWidth, alignment: .leading)
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
                                    assistantBubble(msg, isLast: index == state.promptMessages.count - 1, maxWidth: 450)
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

    func handlePromptInput(_ text: String) {
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
                                    assistantBubble(msg, isLast: index == state.chatMessages.count - 1, maxWidth: 400)
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

    func sendChatMessage(_ message: String) {
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
                                    assistantBubble(msg, isLast: index == state.qaMessages.count - 1, maxWidth: 400)
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

    func askQAQuestion(_ question: String) {
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
}
