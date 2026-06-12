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
    private var instantEditHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    /// Screen bounds of the selection (AppKit bottom-left-origin coordinates)
    /// captured at hotkey time, used to position the panel near the selection.
    private var pendingSelectionRect: NSRect?

    private static let hotKeySignature = OSType(0x5243_4F4E)
    static let spotlightHotKeyID: UInt32 = 1
    static let instantEditHotKeyID: UInt32 = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SettingsManager.shared.hasCompletedOnboarding {
            // Prompt for Accessibility permission if not granted
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        } else {
            // First launch: the onboarding walks through permissions instead
            showOnboarding()
        }

        registerBuiltinTools()
        _ = HistoryManager.shared

        // Setup Python venv in background (first launch installs deps)
        Task { await PythonEnv.shared.setup() }

        setupSpotlightPanel()
        installHotKeyHandler()
        registerGlobalHotKey()
        registerInstantEditHotKey()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(showSpotlight), name: .showSpotlight, object: nil)
        nc.addObserver(self, selector: #selector(hideSpotlight), name: .hideSpotlight, object: nil)
        nc.addObserver(self, selector: #selector(hideSpotlightTemporary), name: .hideSpotlightTemporary, object: nil)
        nc.addObserver(self, selector: #selector(toggleSpotlight), name: .toggleSpotlight, object: nil)
        nc.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
        nc.addObserver(self, selector: #selector(reRegisterHotKey), name: .hotkeyChanged, object: nil)
        nc.addObserver(self, selector: #selector(reRegisterInstantEditHotKey), name: .instantEditHotkeyChanged, object: nil)
        nc.addObserver(self, selector: #selector(runInstantEdit), name: .instantEditTriggered, object: nil)
    }

    private func setupSpotlightPanel() {
        spotlightPanel = SpotlightPanel()
        // Top-aligned so content hugs the panel's top edge while it resizes
        let hostView = NSHostingView(
            rootView: SpotlightView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        hostView.frame = NSRect(x: 0, y: 0, width: 680, height: 420)
        spotlightPanel?.contentView = hostView
        spotlightPanel?.setContentSize(NSSize(width: 680, height: 420))
    }

    @objc func showSpotlight() {
        spotlightPanel?.show(near: pendingSelectionRect)
        pendingSelectionRect = nil
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
            state.freeTargetIsEditable = true
            pendingSelectionRect = nil

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

                // Capture AX selection position (for apply later) and its
                // screen bounds (to position the panel near the selection)
                let systemWide = AXUIElementCreateSystemWide()
                var focRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
                   let focused = focRef {
                    let element = focused as! AXUIElement
                    state.preGrabbedFocusedElement = element
                    state.freeTargetIsEditable = Self.isElementEditable(element)
                    var rangeRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
                       let rangeVal = rangeRef {
                        var range = CFRange(location: 0, length: 0)
                        AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
                        state.freeSelectionStart = range.location

                        if range.length > 0 {
                            self.pendingSelectionRect = Self.selectionScreenBounds(
                                element: element, rangeValue: rangeVal as! AXValue
                            )
                        }
                    }
                }

                // Most apps don't support AX bounds-for-range; fall back to
                // the focused element's frame, then the mouse location, so the
                // panel still opens near the text in contextual mode.
                if state.preGrabbedSelectedText != nil {
                    let elementBounds = state.preGrabbedFocusedElement.flatMap {
                        Self.elementScreenBounds(element: $0)
                    }
                    self.pendingSelectionRect = PanelGeometry.anchorRect(
                        selectionBounds: self.pendingSelectionRect,
                        elementBounds: elementBounds,
                        mouseLocation: NSEvent.mouseLocation
                    )
                }

                state.reset()
                self.showSpotlight()
            }
        }
    }

    /// Whether the element accepts text edits (so Apply can paste over the
    /// selection). PDFs, rendered web pages and read-only fields report their
    /// selection/value as non-settable; Apply then degrades to Copy.
    static func isElementEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        // Unknown: assume editable (legacy behavior)
        return true
    }

    /// Screen frame of an AX element (its position/size attributes), converted
    /// to AppKit bottom-left-origin coordinates.
    static func elementScreenBounds(element: AXUIElement) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pos = posRef, let size = sizeRef else { return nil }

        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &pt),
              AXValueGetValue(size as! AXValue, .cgSize, &sz),
              sz.width > 0, sz.height > 0 else { return nil }

        guard let primary = NSScreen.screens.first else { return nil }
        return PanelGeometry.axRectToAppKit(CGRect(origin: pt, size: sz), primaryScreenHeight: primary.frame.height)
    }

    /// Query the selection's screen bounds via AX and convert them from
    /// top-left-origin (AX) to bottom-left-origin (AppKit) coordinates.
    static func selectionScreenBounds(element: AXUIElement, rangeValue: AXValue) -> NSRect? {
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success, let bounds = boundsRef else { return nil }

        var axRect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &axRect),
              axRect.width > 0 || axRect.height > 0 else { return nil }

        // Primary screen (origin of the global AppKit coordinate space)
        guard let primary = NSScreen.screens.first else { return nil }
        return PanelGeometry.axRectToAppKit(axRect, primaryScreenHeight: primary.frame.height)
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
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    // MARK: - Onboarding

    private var onboardingWindow: NSWindow?

    private func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Raccoon Tools"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    @objc func reRegisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registerGlobalHotKey()
    }

    @objc func reRegisterInstantEditHotKey() {
        if let ref = instantEditHotKeyRef {
            UnregisterEventHotKey(ref)
            instantEditHotKeyRef = nil
        }
        registerInstantEditHotKey()
    }

    @objc func runInstantEdit() {
        // Ignore while the Spotlight panel is open — the selection would be ours
        guard spotlightPanel?.isVisible != true else { return }
        Task { @MainActor in
            InstantEdit.shared.run()
        }
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

    // MARK: - Global Hot Keys

    /// Single Carbon handler dispatching on the EventHotKeyID:
    /// id 1 = Spotlight toggle, id 2 = instant edit.
    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if hotKeyID.id == AppDelegate.instantEditHotKeyID {
                NotificationCenter.default.post(name: .instantEditTriggered, object: nil)
            } else {
                NotificationCenter.default.post(name: .toggleSpotlight, object: nil)
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
        self.eventHandlerRef = handlerRef
    }

    private func registerGlobalHotKey() {
        let settings = SettingsManager.shared
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.spotlightHotKeyID)

        RegisterEventHotKey(
            UInt32(settings.hotKeyCode),
            UInt32(settings.hotKeyModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func registerInstantEditHotKey() {
        let settings = SettingsManager.shared
        guard settings.instantEditEnabled else { return }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.instantEditHotKeyID)
        RegisterEventHotKey(
            UInt32(settings.instantEditKeyCode),
            UInt32(settings.instantEditModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &instantEditHotKeyRef
        )
    }
}

extension Notification.Name {
    static let toggleSpotlight = Notification.Name("toggleSpotlight")
}
