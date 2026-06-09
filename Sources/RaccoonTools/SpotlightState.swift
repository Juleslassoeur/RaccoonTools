import Foundation

struct RunningTaskInfo: Identifiable {
    let id = UUID()
    let toolName: String
    let startTime: Date
    // 0.0–1.0 when the underlying process reports parsable progress, nil otherwise
    var progress: Double? = nil
}

struct PickedColor: Identifiable {
    let id = UUID()
    let date = Date()
    let hex: String
    let r: Int, g: Int, b: Int

    var cssRGB: String { "rgb(\(r), \(g), \(b))" }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let rr = Int(c.redComponent * 255)
        let gg = Int(c.greenComponent * 255)
        let bb = Int(c.blueComponent * 255)
        self.r = rr; self.g = gg; self.b = bb
        self.hex = String(format: "#%02X%02X%02X", rr, gg, bb)
    }
}

struct ResultOption: Identifiable {
    let id = UUID()
    let value: String
    let detail: String
}

struct QAMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String    // mutable so streaming deltas can update it in place (stable id)
    var source: String  // where the LLM found it in the file (empty for user messages)
}

struct PaletteColor: Identifiable {
    let id = UUID()
    let hex: String
    let name: String
    let role: String

    var color: NSColor {
        var hexStr = hex.trimmingCharacters(in: .whitespaces)
        if hexStr.hasPrefix("#") { hexStr = String(hexStr.dropFirst()) }
        guard hexStr.count == 6, let val = UInt64(hexStr, radix: 16) else { return .gray }
        return NSColor(
            red: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }
}

import AppKit

class SpotlightState: ObservableObject {
    static let shared = SpotlightState()

    @Published var input = ""
    @Published var isRunning = false
    @Published var runningToolName = ""
    @Published var resultText: String?
    @Published var showHistory = false
    @Published var historyTab: HistoryTab = .clipboard
    @Published var historySelectedIndex = 0
    @Published var selectedIndex = 0
    @Published var droppedFilePath: String?  // full path stored when file is dropped
    @Published var showColorPicker = false
    @Published var showPalette = false
    @Published var paletteColors: [PaletteColor] = []
    @Published var paletteSelectedIndex = 0
    var paletteCache: [String: [PaletteColor]] = [:]

    // Cap for the in-memory caches below. When a cache hits the cap we just
    // clear it: entries are cheap to recompute (one LLM call) and a session
    // rarely accumulates this many, so an LRU isn't worth the complexity.
    private let cacheCap = 100

    func cachePalette(_ colors: [PaletteColor], for key: String) {
        if paletteCache.count >= cacheCap { paletteCache.removeAll() }
        paletteCache[key] = colors
    }

    func cacheLLMResult(_ result: String, for key: String) {
        if llmCache.count >= cacheCap { llmCache.removeAll() }
        llmCache[key] = result
    }

    // Structured results (for multi-option LLM tools)
    @Published var structuredResults: [ResultOption] = []
    @Published var resultSelectedIndex = 0
    @Published var showStructuredResult = false

    // LLM cache
    var llmCache: [String: String] = [:]

    // History detail view
    @Published var showHistoryDetail = false
    @Published var historyDetailEntry: HistoryEntry?
    @Published var historyDetailOptions: [ResultOption] = []
    @Published var historyDetailSelectedIndex = 0

    // Q&A session
    @Published var showQA = false
    @Published var showChat = false
    @Published var showPrompt = false
    @Published var promptStep: PromptStep = .content
    @Published var promptContent = ""
    @Published var promptInstruction = ""
    @Published var promptMessages: [QAMessage] = []

    // Free (contextual text assistant)
    @Published var showFree = false
    @Published var freeMessages: [QAMessage] = []
    @Published var freeOriginalText = ""
    @Published var freeCurrentText = ""
    // Every successful EDIT response is appended here; the user can navigate
    // versions on the edit card and apply any of them
    @Published var freeVersions: [String] = []
    @Published var freeVersionIndex: Int = 0

    enum PromptStep { case content, instruction, qa, result }
    @Published var qaMessages: [QAMessage] = []
    @Published var chatMessages: [QAMessage] = []
    @Published var qaSelectedIndex = 0
    @Published var qaFilePath: String = ""
    @Published var qaFileContent: String = ""
    @Published var pickedColors: [PickedColor] = []
    @Published var colorSelectedIndex = 0

    // Track which edit messages have been applied (for visual feedback)
    @Published var appliedMessageIDs: Set<UUID> = []
    // Toggle to show/hide original text in free mode header
    @Published var freeShowOriginal = false

    // Whether the focused element the selection came from accepts edits
    // (false for PDFs, web pages, read-only fields — Apply becomes Copy).
    // Lifecycle follows preGrabbed*: set at hotkey time, not by reset().
    @Published var freeTargetIsEditable = true
    // Reference to the app that was frontmost before opening spotlight
    var previousApp: NSRunningApplication?
    // Pre-grabbed from the previous app at hotkey time (before we steal focus)
    var preGrabbedSelectedText: String?
    var preGrabbedFocusedElement: AXUIElement?
    // Track paste position for re-selection via AX
    var freeHasApplied = false
    var freeSelectionStart: Int = 0       // cursor position where the selection began
    var freeLastAppliedText: String = ""  // text currently in the document (for re-selection length)

    // Frecency scores snapshot used for suggestion ordering. Single source of
    // truth shared by the rendered list AND the arrow/Enter key handler — if
    // they computed scores independently, a tool run mutating the history
    // would silently reorder one but not the other and Enter would pick the
    // wrong tool. Refreshed by the view on appear and on input change.
    var suggestionScores: [String: Double] = [:]

    // Background running tasks (visible in menu bar even when spotlight is closed)
    @Published var runningTasks: [RunningTaskInfo] = []

    enum HistoryTab {
        case clipboard
        case images
        case tools
    }

    func reset() {
        input = ""
        isRunning = false
        runningToolName = ""
        resultText = nil
        showHistory = false
        droppedFilePath = nil
        showColorPicker = false
        showPalette = false
        paletteColors = []
        paletteSelectedIndex = 0
        structuredResults = []
        resultSelectedIndex = 0
        showStructuredResult = false
        showHistoryDetail = false
        historyDetailEntry = nil
        historyDetailOptions = []
        historyDetailSelectedIndex = 0
        showQA = false
        showChat = false
        showPrompt = false
        showFree = false
        promptStep = .content
        promptContent = ""
        promptInstruction = ""
        promptMessages = []
        freeMessages = []
        freeOriginalText = ""
        freeCurrentText = ""
        freeVersions = []
        freeVersionIndex = 0
        freeHasApplied = false
        freeLastAppliedText = ""
        appliedMessageIDs = []
        freeShowOriginal = false
        qaMessages = []
        chatMessages = []
        qaSelectedIndex = 0
        qaFilePath = ""
        qaFileContent = ""
        historyTab = .clipboard
        historySelectedIndex = 0
        selectedIndex = 0
        colorSelectedIndex = 0
    }

    func prefill(_ command: String) {
        reset()
        input = command
    }

    func addRunningTask(_ name: String) -> UUID {
        let task = RunningTaskInfo(toolName: name, startTime: Date())
        runningTasks.append(task)
        return task.id
    }

    func removeRunningTask(_ id: UUID) {
        runningTasks.removeAll { $0.id == id }
    }

    func updateTaskProgress(_ id: UUID, _ progress: Double) {
        guard let idx = runningTasks.firstIndex(where: { $0.id == id }) else { return }
        runningTasks[idx].progress = min(max(progress, 0), 1)
    }
}

class ProcessManager {
    static let shared = ProcessManager()
    var processes: [UUID: Process] = [:]

    func register(_ id: UUID, process: Process) {
        processes[id] = process
    }

    func cancel(_ id: UUID? = nil) {
        if let id {
            processes[id]?.terminate()
            processes.removeValue(forKey: id)
        } else {
            // Cancel all
            processes.values.forEach { $0.terminate() }
            processes.removeAll()
        }
    }
}
