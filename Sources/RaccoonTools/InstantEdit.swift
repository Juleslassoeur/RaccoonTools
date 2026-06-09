import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the settings UI when the instant-edit hotkey/enabled state changes.
    static let instantEditHotkeyChanged = Notification.Name("instantEditHotkeyChanged")
    /// Posted by the Carbon hotkey handler when the instant-edit hotkey fires.
    static let instantEditTriggered = Notification.Name("instantEditTriggered")
}

/// Headless contextual edit: grab the current selection with a synthetic
/// Cmd+C, run the configured tool on it, paste the result back with Cmd+V —
/// no panel shown, only a tiny HUD near the mouse.
@MainActor
final class InstantEdit {
    static let shared = InstantEdit()
    private var isRunning = false

    private init() {}

    func run() {
        guard !isRunning else { return }

        let settings = SettingsManager.shared
        guard let (tool, _) = ToolRegistry.shared.resolve(input: settings.instantEditToolPath) else {
            InstantEditHUD.shared.showFailure("Tool not found")
            return
        }

        isRunning = true
        InstantEditHUD.shared.showRunning(tool.fullPath)

        // Snapshot the pasteboard so the synthetic Cmd+C/Cmd+V never destroys
        // the user's clipboard.
        let snapshot = PasteboardSnapshot.take()
        let clipBefore = NSPasteboard.general.changeCount
        Self.postKeystroke(0x08, flags: .maskCommand) // Cmd+C

        Task { @MainActor in
            // Wait for the copy to land without blocking the main thread
            try? await Task.sleep(nanoseconds: 100_000_000)

            var selectedText: String?
            if NSPasteboard.general.changeCount != clipBefore {
                selectedText = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let text = selectedText, !text.isEmpty else {
                PasteboardSnapshot.restore(snapshot)
                HistoryManager.shared.ignoreCurrentChange()
                InstantEditHUD.shared.showFailure("No text selected")
                self.isRunning = false
                return
            }

            do {
                let result = try await tool.handler(text)
                let output = result.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty, !output.hasPrefix("Error") else {
                    throw InstantEditError(message: output.isEmpty ? "Empty result" : output)
                }

                // Paste the result — the source app still has focus since we
                // never opened a panel.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
                Self.postKeystroke(0x09, flags: .maskCommand) // Cmd+V

                // Restore the user's clipboard once the paste has landed
                try? await Task.sleep(nanoseconds: 250_000_000)
                PasteboardSnapshot.restore(snapshot)
                HistoryManager.shared.ignoreCurrentChange()
                InstantEditHUD.shared.showSuccess(tool.fullPath)
            } catch {
                PasteboardSnapshot.restore(snapshot)
                HistoryManager.shared.ignoreCurrentChange()
                InstantEditHUD.shared.showFailure(Self.shortMessage(for: error))
            }
            self.isRunning = false
        }
    }

    static func postKeystroke(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func shortMessage(for error: Error) -> String {
        let message: String
        if let instant = error as? InstantEditError {
            message = instant.message
        } else {
            message = error.localizedDescription
        }
        let oneLine = message.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 60 ? String(oneLine.prefix(60)) + "…" : oneLine
    }
}

struct InstantEditError: Error {
    let message: String
}

// MARK: - HUD

/// Tiny borderless non-activating floating panel near the mouse: spinner while
/// running, then "✓ <tool>" or "✕ <error>", auto-fading after ~1.2s.
@MainActor
final class InstantEditHUD {
    static let shared = InstantEditHUD()

    final class Model: ObservableObject {
        enum Phase { case running, success, failure }
        @Published var phase: Phase = .running
        @Published var text = ""
    }

    private var panel: NSPanel?
    private var hostView: NSHostingView<InstantEditHUDView>?
    private let model = Model()
    private var fadeWorkItem: DispatchWorkItem?

    private init() {}

    func showRunning(_ toolName: String) {
        update(phase: .running, text: toolName)
    }

    func showSuccess(_ toolName: String) {
        update(phase: .success, text: toolName, fadeAfter: 1.2)
    }

    func showFailure(_ message: String) {
        update(phase: .failure, text: message, fadeAfter: 1.2)
    }

    private func update(phase: Model.Phase, text: String, fadeAfter: TimeInterval? = nil) {
        fadeWorkItem?.cancel()
        fadeWorkItem = nil

        model.phase = phase
        model.text = text

        let panel = ensurePanel()
        if let hostView {
            let size = hostView.fittingSize
            panel.setContentSize(size)
        }
        if !panel.isVisible {
            position(panel, near: NSEvent.mouseLocation)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        if let delay = fadeAfter {
            let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
            fadeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let host = NSHostingView(rootView: InstantEditHUDView(model: model))
        panel.contentView = host
        self.hostView = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        var origin = NSPoint(x: point.x + 14, y: point.y + 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - 8 - panel.frame.width)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - 8 - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
    }
}

struct InstantEditHUDView: View {
    @ObservedObject var model: InstantEditHUD.Model

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .running:
                ProgressView().controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            Text(model.text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThickMaterial)
        )
        .fixedSize()
    }
}
