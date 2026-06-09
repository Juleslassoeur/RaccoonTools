import Foundation
import AppKit

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let command: String
    let toolPath: String
    let result: String

    init(command: String, toolPath: String, result: String) {
        self.id = UUID()
        self.date = Date()
        self.command = command
        self.toolPath = toolPath
        self.result = result
    }
}

struct ClipboardEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let content: String  // text content or image file path
    let isImage: Bool

    init(content: String, isImage: Bool = false) {
        self.id = UUID()
        self.date = Date()
        self.content = content
        self.isImage = isImage
    }
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var commandHistory: [HistoryEntry] = []
    @Published var clipboardHistory: [ClipboardEntry] = []

    private let historyFile: URL
    private let clipboardFile: URL
    private let imagesDir: URL
    private var clipboardTimer: Timer?
    private var lastChangeCount: Int = 0

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RaccoonTools")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        historyFile = dir.appendingPathComponent("history.json")
        clipboardFile = dir.appendingPathComponent("clipboard.json")
        imagesDir = dir.appendingPathComponent("clipboard_images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
        lastChangeCount = NSPasteboard.general.changeCount
        startClipboardMonitor()
    }

    func addCommand(_ entry: HistoryEntry) {
        commandHistory.insert(entry, at: 0)
        if commandHistory.count > 200 { commandHistory = Array(commandHistory.prefix(200)) }
        save()
    }

    // MARK: - Frecency

    /// Age-based weights for frecency scoring of executed commands.
    enum FrecencyWeight {
        static let lastHour: Double = 100
        static let lastDay: Double = 80
        static let lastWeek: Double = 30
        static let older: Double = 10

        static let hour: TimeInterval = 3600
        static let day: TimeInterval = 86_400
        static let week: TimeInterval = 7 * 86_400
    }

    /// Maps toolPath → frecency score. Each history entry contributes a
    /// weight based on its age; recent uses count much more than old ones.
    func frecencyScores(now: Date = Date()) -> [String: Double] {
        Self.frecencyScores(for: commandHistory, now: now)
    }

    /// Pure scoring over arbitrary entries (unit-testable).
    static func frecencyScores(for entries: [HistoryEntry], now: Date = Date()) -> [String: Double] {
        var scores: [String: Double] = [:]
        for entry in entries {
            let age = now.timeIntervalSince(entry.date)
            let weight: Double
            if age < FrecencyWeight.hour {
                weight = FrecencyWeight.lastHour
            } else if age < FrecencyWeight.day {
                weight = FrecencyWeight.lastDay
            } else if age < FrecencyWeight.week {
                weight = FrecencyWeight.lastWeek
            } else {
                weight = FrecencyWeight.older
            }
            scores[entry.toolPath, default: 0] += weight
        }
        return scores
    }

    func addClipboard(_ text: String, isImage: Bool = false) {
        if let last = clipboardHistory.first, last.content == text { return }
        clipboardHistory.insert(ClipboardEntry(content: text, isImage: isImage), at: 0)
        // Remove old entries and clean up image files
        if clipboardHistory.count > 50 {
            let removed = clipboardHistory[50...]
            for entry in removed where entry.isImage {
                try? FileManager.default.removeItem(atPath: entry.content)
            }
            clipboardHistory = Array(clipboardHistory.prefix(50))
        }
        save()
    }

    /// Sync the monitor's change count with the pasteboard so the next poll
    /// ignores changes we made ourselves (e.g. the selection grab + restore).
    func ignoreCurrentChange() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Load an image from a clipboard history entry
    func loadImage(for entry: ClipboardEntry) -> NSImage? {
        guard entry.isImage else { return nil }
        return NSImage(contentsOfFile: entry.content)
    }

    private func startClipboardMonitor() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let changeCount = NSPasteboard.general.changeCount
            guard changeCount != self.lastChangeCount else { return }
            self.lastChangeCount = changeCount

            let pb = NSPasteboard.general

            // Skip concealed/transient entries (e.g. password managers)
            let concealedTypes: [String] = [
                "org.nspasteboard.ConcealedType",
                "org.nspasteboard.TransientType",
                "org.nspasteboard.AutoGeneratedType",
                "com.agilebits.onepassword",
            ]
            let pbTypes = pb.types?.map(\.rawValue) ?? []
            if pbTypes.contains(where: { concealedTypes.contains($0) }) {
                return
            }

            // Check for image first
            if let imgData = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
                if let img = NSImage(data: imgData) {
                    // Save image to disk
                    let filename = "img_\(UUID().uuidString).png"
                    let path = self.imagesDir.appendingPathComponent(filename).path
                    if let tiff = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                        DispatchQueue.main.async {
                            self.addClipboard(path, isImage: true)
                        }
                        return
                    }
                }
            }

            // Text
            if let str = pb.string(forType: .string), !str.isEmpty {
                DispatchQueue.main.async {
                    self.addClipboard(str)
                }
            }
        }
    }

    private func save() {
        try? JSONEncoder().encode(commandHistory).write(to: historyFile)
        try? JSONEncoder().encode(clipboardHistory).write(to: clipboardFile)
    }

    private func load() {
        if let data = try? Data(contentsOf: historyFile) {
            commandHistory = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: clipboardFile) {
            clipboardHistory = (try? JSONDecoder().decode([ClipboardEntry].self, from: data)) ?? []
        }
    }
}
