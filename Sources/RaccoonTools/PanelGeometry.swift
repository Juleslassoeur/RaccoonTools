import CoreGraphics
import Foundation

/// Pure geometry helpers for the Spotlight panel: adaptive height clamping,
/// AX → AppKit coordinate conversion, and contextual placement near a text
/// selection. Kept free of AppKit so the logic is unit-testable.
enum PanelGeometry {
    static let panelWidth: CGFloat = 680
    static let minPanelHeight: CGFloat = 96
    static let maxPanelHeight: CGFloat = 480
    /// Gap between the selection rect and the panel edge.
    static let selectionMargin: CGFloat = 8
    /// Minimum distance kept from the screen's visible frame edges.
    static let screenMargin: CGFloat = 12

    /// Clamp a reported SwiftUI content height into the panel's allowed range.
    static func clampedHeight(_ contentHeight: CGFloat) -> CGFloat {
        min(max(contentHeight, minPanelHeight), maxPanelHeight)
    }

    /// AX coordinates are top-left-origin (global display space); AppKit screen
    /// coordinates are bottom-left-origin relative to the primary screen.
    static func axRectToAppKit(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Maximum height for a focused element to be a useful placement anchor —
    /// larger elements (a whole web area or document view) say nothing about
    /// where the selected text actually is.
    static let maxAnchorElementHeight: CGFloat = 220

    /// Best available anchor for contextual placement: the selection bounds
    /// when the app exposes them, else the focused element's frame when it is
    /// reasonably small (a text field, not a whole document), else a thin rect
    /// at the mouse location — the user usually just selected text there.
    static func anchorRect(selectionBounds: CGRect?, elementBounds: CGRect?, mouseLocation: CGPoint) -> CGRect {
        if let sel = selectionBounds, sel.width > 0 || sel.height > 0 {
            return sel
        }
        if let el = elementBounds, el.width > 0, el.height > 0, el.height <= maxAnchorElementHeight {
            return el
        }
        return CGRect(x: mouseLocation.x, y: mouseLocation.y - 10, width: 1, height: 20)
    }

    /// Default position: horizontally centered, in the upper third of the screen.
    static func centeredOrigin(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - visibleFrame.height * 0.3
        )
    }

    /// Bottom-left origin for the panel given an optional selection rect
    /// (AppKit coordinates). Prefers just below the selection, falls back to
    /// above it, and finally clamps inside the visible frame. Falls back to
    /// the centered position when no usable selection rect is available.
    static func panelOrigin(panelSize: CGSize, selectionRect: CGRect?, visibleFrame: CGRect) -> CGPoint {
        guard let sel = selectionRect, sel.width > 0 || sel.height > 0 else {
            return centeredOrigin(panelSize: panelSize, visibleFrame: visibleFrame)
        }
        return contextualOrigin(panelSize: panelSize, selectionRect: sel, visibleFrame: visibleFrame)
    }

    /// Position just below the selection (or above it when there is no room
    /// below), clamped to the screen's visible frame so the panel never
    /// overlaps the selection when avoidable.
    static func contextualOrigin(panelSize: CGSize, selectionRect: CGRect, visibleFrame: CGRect) -> CGPoint {
        let minX = visibleFrame.minX + screenMargin
        let maxX = visibleFrame.maxX - screenMargin - panelSize.width
        let x = min(max(selectionRect.minX, minX), max(minX, maxX))

        // Preferred: below the selection (panel top sits just under it).
        let belowY = selectionRect.minY - selectionMargin - panelSize.height
        if belowY >= visibleFrame.minY + screenMargin {
            return CGPoint(x: x, y: belowY)
        }

        // Otherwise: above the selection.
        let aboveY = selectionRect.maxY + selectionMargin
        if aboveY + panelSize.height <= visibleFrame.maxY - screenMargin {
            return CGPoint(x: x, y: aboveY)
        }

        // No room on either side: clamp inside the screen (overlap unavoidable).
        let minY = visibleFrame.minY + screenMargin
        let maxY = visibleFrame.maxY - screenMargin - panelSize.height
        let y = min(max(belowY, minY), max(minY, maxY))
        return CGPoint(x: x, y: y)
    }
}
