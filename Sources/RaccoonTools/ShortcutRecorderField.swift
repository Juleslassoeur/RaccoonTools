import Carbon
import SwiftUI

/// Click-to-record shortcut field, the standard macOS pattern: click it,
/// press any combination you want, done. Esc cancels. Combinations must
/// include ⌘, ⌃ or ⌥ so a bare letter can't hijack normal typing.
struct ShortcutRecorderField: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    /// Called after a new combination is captured (e.g. to re-register).
    var onChange: () -> Void = {}

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? cancelRecording() : startRecording()
            } label: {
                Text(isRecording ? "Type shortcut…" : KeyComboFormatter.string(keyCode: keyCode, modifiers: modifiers))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 120)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press the combination (Esc cancels)" : "Click, then press the combination you want")

            if isRecording {
                Text(hint ?? "press the keys — Esc cancels")
                    .font(.caption)
                    .foregroundColor(hint == nil ? .secondary : .orange)
            }
        }
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        isRecording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil  // swallow keystrokes while recording
        }
    }

    private func cancelRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        hint = nil
    }

    private func handle(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            cancelRecording()
            return
        }
        // Ignore bare modifier presses (flagsChanged isn't monitored, but
        // some keyboards emit keyDown for them)
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierKeyCodes.contains(Int(event.keyCode)) else { return }

        var carbon = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }

        guard carbon & (cmdKey | optionKey | controlKey) != 0 else {
            hint = "include ⌘, ⌃ or ⌥ — a bare key would hijack typing"
            return
        }

        keyCode = Int(event.keyCode)
        modifiers = carbon
        cancelRecording()
        onChange()
    }
}
