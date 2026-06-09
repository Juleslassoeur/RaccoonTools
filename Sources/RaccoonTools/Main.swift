import SwiftUI
import Carbon

@main
struct RaccoonToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(nsImage: RaccoonIcon.menuBarIcon())
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var spotlightPanel: SpotlightPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prompt for Accessibility permission if not granted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        registerBuiltinTools()
        _ = HistoryManager.shared

        // Setup Python venv in background (first launch installs deps)
        Task { await PythonEnv.shared.setup() }

        setupSpotlightPanel()
        registerGlobalHotKey()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(showSpotlight), name: .showSpotlight, object: nil)
        nc.addObserver(self, selector: #selector(hideSpotlight), name: .hideSpotlight, object: nil)
        nc.addObserver(self, selector: #selector(hideSpotlightTemporary), name: .hideSpotlightTemporary, object: nil)
        nc.addObserver(self, selector: #selector(toggleSpotlight), name: .toggleSpotlight, object: nil)
        nc.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
        nc.addObserver(self, selector: #selector(reRegisterHotKey), name: .hotkeyChanged, object: nil)
    }

    private func setupSpotlightPanel() {
        spotlightPanel = SpotlightPanel()
        let hostView = NSHostingView(rootView: SpotlightView())
        hostView.frame = NSRect(x: 0, y: 0, width: 680, height: 420)
        spotlightPanel?.contentView = hostView
        spotlightPanel?.setContentSize(NSSize(width: 680, height: 420))
    }

    @objc func showSpotlight() {
        spotlightPanel?.show()
        // Focus text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let contentView = self?.spotlightPanel?.contentView {
                self?.focusTextField(in: contentView)
            }
        }
    }

    @objc func hideSpotlight() {
        spotlightPanel?.hide()
        SpotlightState.shared.reset()
    }

    @objc func hideSpotlightTemporary() {
        // Hide panel without resetting state (for color picker)
        spotlightPanel?.orderOut(nil)
    }

    @objc func toggleSpotlight() {
        // Close settings if open
        if let w = settingsWindow, w.isVisible {
            w.orderOut(nil)
        }

        if spotlightPanel?.isVisible == true {
            hideSpotlight()
        } else {
            let state = SpotlightState.shared
            state.previousApp = NSWorkspace.shared.frontmostApplication
            state.preGrabbedSelectedText = nil
            state.preGrabbedFocusedElement = nil

            // Grab selected text while previous app is still frontmost.
            // Snapshot the pasteboard first so the synthetic Cmd+C never
            // destroys the user's clipboard.
            let snapshot = PasteboardSnapshot.take()
            let clipBefore = NSPasteboard.general.changeCount
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Wait for the copy to land without blocking the main thread
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)

                if NSPasteboard.general.changeCount != clipBefore,
                   let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    state.preGrabbedSelectedText = text
                }

                // Restore the user's clipboard and make sure the grab never
                // shows up in clipboard history
                PasteboardSnapshot.restore(snapshot)
                HistoryManager.shared.ignoreCurrentChange()

                // Capture AX selection position (for apply later)
                let systemWide = AXUIElementCreateSystemWide()
                var focRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
                   let focused = focRef {
                    state.preGrabbedFocusedElement = (focused as! AXUIElement)
                    var rangeRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
                       let rangeVal = rangeRef {
                        var range = CFRange(location: 0, length: 0)
                        AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
                        state.freeSelectionStart = range.location
                    }
                }

                state.reset()
                self.showSpotlight()
            }
        }
    }

    var settingsWindow: NSWindow?

    @objc func openSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Raccoon Tools Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 500))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    @objc func reRegisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registerGlobalHotKey()
    }

    private func focusTextField(in view: NSView) {
        for subview in view.subviews {
            if let tf = subview as? NSTextField, tf.isEditable {
                spotlightPanel?.makeFirstResponder(tf)
                return
            }
            focusTextField(in: subview)
        }
    }

    // MARK: - Global Hot Key

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            NotificationCenter.default.post(name: .toggleSpotlight, object: nil)
            return noErr
        }

        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
        self.eventHandlerRef = handlerRef

        let settings = SettingsManager.shared
        let hotKeyID = EventHotKeyID(signature: OSType(0x5243_4F4E), id: 1)

        RegisterEventHotKey(
            UInt32(settings.hotKeyCode),
            UInt32(settings.hotKeyModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

extension Notification.Name {
    static let toggleSpotlight = Notification.Name("toggleSpotlight")
}
