import AppKit
import SwiftUI

/// PreferenceKey used by SpotlightView to report its natural content height.
struct SpotlightContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension Notification.Name {
    /// Posted by SpotlightView whenever its natural content height changes.
    /// userInfo: ["height": CGFloat]
    static let spotlightContentHeightChanged = Notification.Name("spotlightContentHeightChanged")
}

class SpotlightPanel: NSPanel {
    private var heightObserver: NSObjectProtocol?
    /// False until the first content-height layout has been applied —
    /// the very first resize must not animate.
    private var hasPerformedInitialLayout = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        heightObserver = NotificationCenter.default.addObserver(
            forName: .spotlightContentHeightChanged, object: nil, queue: .main
        ) { [weak self] note in
            guard let height = note.userInfo?["height"] as? CGFloat else { return }
            self?.adjustHeight(toContentHeight: height)
        }
    }

    deinit {
        if let observer = heightObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Show the panel. When a selection rect (AppKit bottom-left-origin screen
    /// coordinates) is provided, position the panel just below it (or above
    /// when there is no room below). Otherwise center in the upper third.
    func show(near selectionRect: NSRect? = nil) {
        if let screen = screenFor(selectionRect) {
            let origin = PanelGeometry.panelOrigin(
                panelSize: frame.size,
                selectionRect: selectionRect,
                visibleFrame: screen.visibleFrame
            )
            setFrameOrigin(origin)
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func hide() {
        orderOut(nil)
        NSApp.hide(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
        SpotlightState.shared.reset()
    }

    // MARK: - Adaptive height

    /// Resize the panel to hug the SwiftUI content, keeping the TOP edge fixed
    /// (the panel grows downward). Animated except on first layout / while hidden.
    private func adjustHeight(toContentHeight contentHeight: CGFloat) {
        var target = PanelGeometry.clampedHeight(contentHeight)

        // The top edge must NEVER move up (it sits just below the selection in
        // contextual mode — rising would cover the text being edited). If the
        // screen bottom limits downward growth, cap the height instead.
        if let screen = self.screen ?? NSScreen.main {
            let minY = screen.visibleFrame.minY + PanelGeometry.screenMargin
            target = min(target, frame.maxY - minY)
        }

        // Avoid feedback loops: only react to meaningful changes
        guard abs(target - frame.height) > 1 else { return }

        var newFrame = frame
        newFrame.origin.y = frame.maxY - target  // top edge stays fixed
        newFrame.size.height = target

        let shouldAnimate = isVisible && hasPerformedInitialLayout
        hasPerformedInitialLayout = true

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    /// Screen containing the selection rect, else the main screen.
    private func screenFor(_ selectionRect: NSRect?) -> NSScreen? {
        if let rect = selectionRect,
           let match = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
            return match
        }
        return NSScreen.main
    }
}
