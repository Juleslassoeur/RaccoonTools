import Foundation
import AppKit

/// Definition from the user's enabled macOS dictionaries (offline). Returns
/// nil when no dictionary knows the word. French works when a French
/// dictionary is enabled in Dictionary.app's preferences.
func systemDictionaryDefinition(for word: String) -> String? {
    let range = CFRange(location: 0, length: word.utf16.count)
    guard range.length > 0,
          let definition = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() else {
        return nil
    }
    return (definition as String).trimmingCharacters(in: .whitespacesAndNewlines)
}

func registerTextTools(registry: ToolRegistry, settings: SettingsManager) {
    // ============================================================
    // MARK: - TRANSLATE
    // ============================================================

    registry.register(ToolCommand(
        path: ["translate"],
        description: "Translate text — pick a target: translate en / fr / es (or :de)",
        parameterName: "text :lang",
        handler: { input in
            guard !input.isEmpty else { return "Error: usage: translate [text] [lang], or select text and type a language like: translate es" }

            let request = parseTranslateInput(input, default: settings.defaultTranslateTarget)
            let targetLang = request.target
            let textToTranslate = request.text
            guard !textToTranslate.isEmpty else { return "Error: no text to translate" }

            // Check settings: CLI (Google) or LLM
            if settings.translateMode == "llm" {
                let toolPath = "translate"
                let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
                let provider = settings.getProvider(for: toolPath)
                let langName = TranslateLang.names[targetLang] ?? targetLang
                return try await LLMService.call(provider: provider, systemPrompt: prompt,
                    userMessage: "Translate to \(langName): \(textToTranslate)")
            }

            // CLI mode: translate-shell (Google Translate)
            let trans = try await ensureDep("trans", brew: "translate-shell")

            // Detect source language first
            let detected = try await shellExec(trans, args: ["-id", "-no-ansi", "-b", textToTranslate])
            var sourceLang = detected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // -id returns something like "fr" or "French"
            if sourceLang.count > 3 { sourceLang = "" }

            // If detected source == target, flip to a sensible default
            if sourceLang == targetLang || sourceLang.isEmpty {
                sourceLang = targetLang == "en" ? "fr" : "en"
            }

            // Brief translation (just the result)
            let brief = try await shellExec(trans, args: [
                "-b", "-no-ansi", "-s", sourceLang, "-t", targetLang, textToTranslate
            ])
            let result = brief.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { return "Error: no translation found" }
            return result
        }
    ))

    // ============================================================
    // MARK: - REPHRASE tools
    // ============================================================

    for (context, desc) in [
        ("mail", "Rephrase text as a professional email"),
        ("msg", "Rephrase text as a casual message"),
        ("teams", "Rephrase text for Teams/Slack"),
        ("idea", "Rephrase and structure a rough idea"),
    ] {
        let toolPath = "rephrase \(context)"
        registry.register(ToolCommand(
            path: ["rephrase", context],
            description: desc,
            parameterName: "text",
            usesLLM: true,
            handler: { [toolPath] input in
                guard !input.isEmpty else { return "Error: please provide text to rephrase" }
                let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
                let provider = settings.getProvider(for: toolPath)
                return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: input)
            }
        ))
    }

    // ============================================================
    // MARK: - DEF
    // ============================================================

    registry.register(ToolCommand(
        path: ["def"],
        description: "Get the definition of a word",
        parameterName: "word",
        usesLLM: true,
        handler: { word in
            guard !word.isEmpty else { return "Error: please provide a word" }
            // Offline engine: the user's macOS dictionaries (Dictionary.app).
            // Falls back to the LLM when the word isn't found.
            if settings.dictionaryEngine == "system",
               let definition = systemDictionaryDefinition(for: word.trimmingCharacters(in: .whitespaces)) {
                return definition
            }
            let toolPath = "def"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: word)
        }
    ))

    // ============================================================
    // MARK: - EXPLAIN
    // ============================================================

    registry.register(ToolCommand(
        path: ["explain"],
        description: "Get a concise explanation of a concept",
        parameterName: "concept",
        usesLLM: true,
        handler: { concept in
            guard !concept.isEmpty else { return "Error: please provide a concept" }
            let toolPath = "explain"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: concept)
        }
    ))

    // ============================================================
    // MARK: - SUMMARIZE
    // ============================================================

    // summarize txt — paste or type text directly
    registry.register(ToolCommand(
        path: ["summarize", "txt"],
        description: "Summarize pasted text",
        parameterName: "text",
        usesLLM: true,
        handler: { text in
            guard !text.isEmpty else { return "Error: paste or type the text to summarize" }
            let toolPath = "summarize txt"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // summarize link — fetches webpage then summarizes
    registry.register(ToolCommand(
        path: ["summarize", "link"],
        description: "Summarize a webpage",
        parameterName: "url",
        usesLLM: true,
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a URL" }
            let html = try await shellExec("/usr/bin/curl", args: ["-sL", "--max-time", "15", url])
            let text = stripHTML(html)
            guard !text.isEmpty else { return "Error: could not fetch content from \(url)" }
            let truncated = truncateForLLM(text)
            let toolPath = "summarize link"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: "URL: \(url)\n\nContent:\n\(truncated)")
        }
    ))

    // summarize video — fetches YouTube transcript then summarizes
    registry.register(ToolCommand(
        path: ["summarize", "video"],
        description: "Summarize a YouTube video",
        parameterName: "url",
        usesLLM: true,
        handler: { url in
            guard !url.isEmpty else { return "Error: please provide a YouTube URL" }
            let ytdlp = try await ensureDep("yt-dlp", brew: "yt-dlp")

            // Download subtitles to temp dir
            let tmpDir = NSTemporaryDirectory() + "raccoon_\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: tmpDir) }

            _ = try? await shellExec(ytdlp, args: [
                "--write-auto-sub", "--sub-lang", "en",
                "--skip-download", "-o", "\(tmpDir)/subs", url
            ])

            // Find and read the subtitle file
            let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
            let subFile = files.first { $0.hasSuffix(".vtt") || $0.hasSuffix(".srt") }
            guard let subFile else { return "Error: no subtitles found for this video" }

            let raw = try String(contentsOfFile: "\(tmpDir)/\(subFile)", encoding: .utf8)
            let transcript = vttToPlainText(raw)
            guard !transcript.isEmpty else { return "Error: transcript is empty" }

            let truncated = truncateForLLM(transcript)
            let toolPath = "summarize video"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: "Video: \(url)\n\nTranscript:\n\(truncated)")
        }
    ))

    // summarize file — drag & drop a file to summarize
    registry.register(ToolCommand(
        path: ["summarize", "file"],
        description: "Summarize a local file (drag & drop)",
        parameterName: "path",
        usesLLM: true,
        handler: { filePath in
            guard !filePath.isEmpty else { return "Error: drag & drop a file or provide a path" }
            let expanded = (filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            // Works for text, PDF, docx, images (OCR) and audio/video
            // (Whisper transcription) via the shared extractor
            let content = try await extractFileText(path: expanded, taskLabel: "summarize file")
            guard !content.isEmpty else { return "Error: no readable text in this file" }
            let truncated = truncateForLLM(content)
            let filename = (expanded as NSString).lastPathComponent
            let toolPath = "summarize file"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: "File: \(filename)\n\nContent:\n\(truncated)")
        }
    ))

    // ============================================================
    // MARK: - SYNONYM
    // ============================================================

    registry.register(ToolCommand(
        path: ["synonym"],
        description: "List synonyms with definitions",
        parameterName: "word",
        usesLLM: true,
        handler: { input in
            guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return "Error: provide a word" }
            let prompt = settings.getSystemPrompt(for: "synonym", default: "List 5-8 synonyms for the given word. Return ONLY a JSON array, no other text. Format: [{\"word\":\"...\",\"def\":\"...\"}] where def is a brief definition with usage nuance.")
            let provider = settings.getProvider(for: "synonym")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: input)
        }
    ))

    // ============================================================
    // MARK: - WORD (reverse dictionary)
    // ============================================================

    registry.register(ToolCommand(
        path: ["word"],
        description: "Find words that match a description",
        parameterName: "description",
        usesLLM: true,
        handler: { input in
            guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return "Error: describe what you're looking for" }
            let prompt = settings.getSystemPrompt(for: "word", default: "You are a reverse dictionary. The user describes something and you find the exact words for it. Return ONLY a JSON array, no other text. Format: [{\"word\":\"...\",\"def\":\"...\"}] with 5-8 precise, specific words. Prioritize uncommon words. Include language origin in def if interesting.")
            let provider = settings.getProvider(for: "word")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: input)
        }
    ))

    // ============================================================
    // MARK: - FIX GRAMMAR
    // ============================================================

    registry.register(ToolCommand(
        path: ["fix", "grammar"],
        description: "Fix grammar and spelling in text or clipboard",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            // If no input, use clipboard
            if text.isEmpty {
                text = NSPasteboard.general.string(forType: .string) ?? ""
            }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            // Free LanguageTool engine when selected (LLM fallback on error)
            if settings.grammarEngine == "languagetool" {
                if let corrected = try? await LanguageTool.correct(text, onlySpelling: false) {
                    return corrected
                }
            }
            let toolPath = "fix grammar"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    registry.register(ToolCommand(
        path: ["fix", "orth"],
        description: "Fix spelling/typos in text or clipboard",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            // Free LanguageTool engine when selected — spelling issues only
            if settings.grammarEngine == "languagetool" {
                if let corrected = try? await LanguageTool.correct(text, onlySpelling: true) {
                    return corrected
                }
            }
            let prompt = settings.getSystemPrompt(for: "fix orth", default: "Fix only spelling and typos in the following text. Do NOT change grammar, punctuation, or style. Return only the corrected text, no explanations.")
            let provider = settings.getProvider(for: "fix orth")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // fix code — fix bugs/errors in code from clipboard or input
    registry.register(ToolCommand(
        path: ["fix", "code"],
        description: "Fix bugs and errors in code (text or clipboard)",
        parameterName: "code",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no code provided and clipboard is empty" }
            let prompt = settings.getSystemPrompt(for: "fix code", default: "Fix the bugs, errors, and issues in the following code. Return ONLY the corrected code, no explanations, no markdown code fences. Preserve the original language and style.")
            let provider = settings.getProvider(for: "fix code")
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // ============================================================
    // MARK: - REPHRASE FORMAL / CASUAL
    // ============================================================

    registry.register(ToolCommand(
        path: ["rephrase", "formal"],
        description: "Rephrase text in a formal tone",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "rephrase formal"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    registry.register(ToolCommand(
        path: ["rephrase", "casual"],
        description: "Rephrase text in a casual tone",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "rephrase casual"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))

    // ============================================================
    // MARK: - SUBJECT
    // ============================================================

    registry.register(ToolCommand(
        path: ["subject"],
        description: "Generate email subject line from text or clipboard",
        parameterName: "text",
        usesLLM: true,
        handler: { input in
            var text = input.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = NSPasteboard.general.string(forType: .string) ?? "" }
            guard !text.isEmpty else { return "Error: no text provided and clipboard is empty" }
            let toolPath = "subject"
            let prompt = settings.getSystemPrompt(for: toolPath, default: LLMToolPrompts.defaults[toolPath]!)
            let provider = settings.getProvider(for: toolPath)
            return try await LLMService.call(provider: provider, systemPrompt: prompt, userMessage: text)
        }
    ))
}

// MARK: - LLM input truncation

// Cap content sent to the LLM (~25-30k tokens, safe for all supported models)
// and append an explicit marker when truncation actually happens.
func truncateForLLM(_ text: String, limit: Int = 100_000) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit)) + "\n\n[content truncated]"
}
