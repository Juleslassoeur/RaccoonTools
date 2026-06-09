# RaccoonTools

[![CI](https://github.com/Juleslassoeur/RaccoonTools/actions/workflows/ci.yml/badge.svg)](https://github.com/Juleslassoeur/RaccoonTools/actions/workflows/ci.yml)

A macOS spotlight-style launcher with built-in tools and a contextual AI writing assistant. Select text in any app, press a hotkey, and edit/translate/rephrase/ask questions about it — all without leaving your workflow.

## Install

```bash
git clone https://github.com/Juleslassoeur/RaccoonTools.git
cd RaccoonTools
chmod +x build.sh
./build.sh
```

Requires: macOS 13+, Swift 5.9+, Homebrew (for some tools).

On first launch, grant **Accessibility** permission in System Settings > Privacy & Security > Accessibility.

## How it works

**Hotkey** (default `Option+Cmd+Space`) opens the launcher. Two modes:

### 1. Text selected = contextual mode

Select text in any app, press the hotkey. RaccoonTools captures the selection automatically.

- **Type an instruction** ("make it shorter", "translate to spanish") — the AI edits your text
- **Type a tool name** (`fix grammar`, `rephrase formal`, `synonym`) — the tool runs on the selected text
- **Enter** = apply the edit back to your document
- **Undo** button = restore the original text
- Keep chatting to refine. Chain tools. The whole exchange is a single multi-turn conversation, and responses stream in as they're generated.

Your clipboard is never clobbered: the selection grab and the apply-edit paste both snapshot and restore whatever you had copied, and neither shows up in the clipboard history.

### 2. No text selected = tool launcher

Browse and run tools with arrow keys, Tab to autocomplete, Enter to execute.

## Tools

| Tool | Description |
|---|---|
| `translate` | Translate text (default target language configurable) |
| `fix grammar` | Fix grammar and spelling |
| `fix orth` | Fix only spelling/typos |
| `rephrase msg` | Rephrase as casual message |
| `rephrase mail` | Rephrase as professional email |
| `rephrase formal` | Formal tone |
| `rephrase casual` | Casual tone |
| `rephrase idea` | Structure a rough idea |
| `def` | Define a word |
| `explain` | Explain a concept |
| `synonym` | List synonyms (arrow-key selectable) |
| `word` | Reverse dictionary |
| `summarize txt` | Summarize pasted text |
| `summarize link` | Summarize a webpage |
| `summarize video` | Summarize a YouTube video |
| `summarize file` | Summarize a local file |
| `get youtube sound` | Download YouTube audio (MP3) |
| `get youtube video` | Download YouTube video |
| `get youtube transcript` | Download subtitles as .txt |
| `get file transcript` | Transcribe audio/video (Whisper) |
| `get file text` | Extract text from PDF/docx/image (OCR) |
| `get file metadata` | Show file metadata |
| `get file links` | Extract URLs from a file |
| `get link txt` | Save webpage as plain text |
| `file to pdf` | Convert file/images to PDF |
| `file to markdown` | Convert PDF/docx to markdown |
| `file compress` | Compress an image |
| `file qa` | Chat with a file |
| `color` | Pick colors + auto palette generator |
| `subject` | Generate email subject line |
| `google` | Search Google |
| `meet` | Create Google Meet link |
| `wifi` | Show WiFi name and password |
| `history` | Browse clipboard history |
| `chat` | Free multi-turn chat with LLM (streaming) |
| `prompt` | Content + instructions workflow |

## Keyboard shortcuts

| Key | Action |
|---|---|
| `Option+Cmd+Space` | Open/close launcher (configurable) |
| `Enter` | Execute tool / apply edit / send message |
| `Tab` | Autocomplete tool name |
| `Arrow Up/Down` | Navigate suggestions |
| `Arrow Right` | Enter tool folder |
| `Arrow Left` | Go back / exit chat |
| `Escape` | Close or go back |
| Drag & drop | Drop files onto the launcher |

## Settings

Open from the menu bar icon > Settings.

- **LLM Providers** — Configure Claude (default model `claude-sonnet-4-6`), OpenAI, Gemini, Ollama, or custom OpenAI-compatible endpoints
- **Tools** — Assign a specific LLM provider and customize the system prompt per tool
- **Translate** — Default target language, engine (Google CLI or LLM)
- **Tone & Style Rules** — Global rules injected into every LLM prompt (e.g. "Never use Hey", "Always be formal")
- **Response Language** — Force LLM to respond in a specific language or auto-detect

## Architecture

Single Swift Package, no dependencies beyond macOS system frameworks.

```
Sources/RaccoonTools/
  Main.swift                 — App entry, hotkey, text capture
  SpotlightPanel.swift       — Floating panel (NSPanel)
  SpotlightView.swift        — Main launcher UI (SwiftUI)
  SpotlightChatViews.swift   — Chat UI + streaming LLM helpers
  SpotlightFreeMode.swift    — Contextual text assistant view
  SpotlightColorViews.swift  — Color tool (history + palette)
  SpotlightHistoryViews.swift — Clipboard history view
  SpotlightState.swift       — App state
  CommandSystem.swift        — Tool registry, matching, tree navigation
  BuiltinTools.swift         — Tool registration
  Tools+Text.swift           — Text/LLM tools
  Tools+Files.swift          — File tools (PDF, OCR, transcripts…)
  Tools+YouTube.swift        — YouTube download/summarize tools
  Tools+System.swift         — System tools (wifi, meet, google…)
  ToolPrompts.swift          — Default system prompts for LLM tools
  ShellExec.swift            — Shell execution + dependency management
  LLMService.swift           — Claude/OpenAI/Gemini/Ollama API calls (streaming, multi-turn)
  FreeReplyParser.swift      — EDIT/ANSWER reply protocol parsing
  PasteboardSnapshot.swift   — Clipboard snapshot/restore around synthetic copy/paste
  SettingsManager.swift      — Persistent settings
  SettingsView.swift         — Settings UI
  HistoryManager.swift       — Clipboard & command history
  KeychainHelper.swift       — API keys in Keychain
  PythonEnv.swift            — Python venv for PDF/OCR tools
  MenuBarView.swift          — Menu bar UI
  RaccoonIcon.swift          — Menu bar icon
```

Unit tests live in `Tests/RaccoonToolsTests` — run them with `swift test`.

## License

MIT
