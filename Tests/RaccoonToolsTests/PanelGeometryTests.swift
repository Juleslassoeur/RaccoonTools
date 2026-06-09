import Testing
import CoreGraphics
@testable import RaccoonTools

@Suite struct PanelGeometryTests {

    // Typical visible frame: 1440×900 display with menu bar + dock
    let visible = CGRect(x: 0, y: 80, width: 1440, height: 795)
    let panelSize = CGSize(width: 680, height: 420)

    // MARK: - Height clamping

    @Test func clampedHeightWithinRangeIsUnchanged() {
        #expect(PanelGeometry.clampedHeight(300) == 300)
    }

    @Test func clampedHeightEnforcesMin() {
        #expect(PanelGeometry.clampedHeight(10) == PanelGeometry.minPanelHeight)
        #expect(PanelGeometry.clampedHeight(-50) == PanelGeometry.minPanelHeight)
    }

    @Test func clampedHeightEnforcesMax() {
        #expect(PanelGeometry.clampedHeight(2000) == PanelGeometry.maxPanelHeight)
    }

    // MARK: - AX → AppKit conversion

    @Test func axRectConversionFlipsY() {
        // AX: top-left origin. Rect 20pt tall whose top is 100pt below the
        // top of a 900pt-tall primary screen.
        let ax = CGRect(x: 250, y: 100, width: 300, height: 20)
        let converted = PanelGeometry.axRectToAppKit(ax, primaryScreenHeight: 900)
        #expect(converted == CGRect(x: 250, y: 780, width: 300, height: 20))
    }

    @Test func axRectConversionRoundTripsTopAndBottom() {
        let ax = CGRect(x: 0, y: 0, width: 100, height: 50)
        let converted = PanelGeometry.axRectToAppKit(ax, primaryScreenHeight: 900)
        // Top of screen in AX (y=0) is top of screen in AppKit (maxY = 900)
        #expect(converted.maxY == 900)
        #expect(converted.minY == 850)
    }

    // MARK: - Contextual placement

    @Test func panelGoesBelowSelectionWhenRoom() {
        let selection = CGRect(x: 200, y: 600, width: 300, height: 20)
        let origin = PanelGeometry.panelOrigin(panelSize: panelSize, selectionRect: selection, visibleFrame: visible)
        // Panel top sits just below the selection bottom
        #expect(origin.y == 600 - PanelGeometry.selectionMargin - panelSize.height)
        #expect(origin.x == 200)
        // Never overlaps the selection
        let panelRect = CGRect(origin: origin, size: panelSize)
        #expect(!panelRect.intersects(selection))
    }

    @Test func panelGoesAboveSelectionWhenNoRoomBelow() {
        let selection = CGRect(x: 200, y: 200, width: 300, height: 20)
        let origin = PanelGeometry.panelOrigin(panelSize: panelSize, selectionRect: selection, visibleFrame: visible)
        // Panel bottom sits just above the selection top
        #expect(origin.y == selection.maxY + PanelGeometry.selectionMargin)
        let panelRect = CGRect(origin: origin, size: panelSize)
        #expect(!panelRect.intersects(selection))
        // Still fully inside the visible frame
        #expect(panelRect.maxY <= visible.maxY)
    }

    @Test func panelClampsInsideScreenWhenNoRoomEitherSide() {
        // Short screen: a 480pt panel cannot fit above or below the selection
        let shortVisible = CGRect(x: 0, y: 0, width: 1440, height: 600)
        let tallPanel = CGSize(width: 680, height: 480)
        let selection = CGRect(x: 200, y: 290, width: 300, height: 20)
        let origin = PanelGeometry.panelOrigin(panelSize: tallPanel, selectionRect: selection, visibleFrame: shortVisible)
        let panelRect = CGRect(origin: origin, size: tallPanel)
        #expect(panelRect.minY >= shortVisible.minY)
        #expect(panelRect.maxY <= shortVisible.maxY)
    }

    @Test func panelClampsHorizontallyToScreenEdges() {
        // Selection near the right edge
        let right = CGRect(x: 1400, y: 600, width: 30, height: 20)
        let originRight = PanelGeometry.panelOrigin(panelSize: panelSize, selectionRect: right, visibleFrame: visible)
        #expect(originRight.x == visible.maxX - PanelGeometry.screenMargin - panelSize.width)

        // Selection partially off the left edge
        let left = CGRect(x: -50, y: 600, width: 30, height: 20)
        let originLeft = PanelGeometry.panelOrigin(panelSize: panelSize, selectionRect: left, visibleFrame: visible)
        #expect(originLeft.x == visible.minX + PanelGeometry.screenMargin)
    }

    @Test func nilSelectionFallsBackToCenteredUpperThird() {
        let origin = PanelGeometry.panelOrigin(panelSize: panelSize, selectionRect: nil, visibleFrame: visible)
        #expect(origin.x == visible.midX - panelSize.width / 2)
        #expect(origin.y == visible.maxY - visible.height * 0.3)
    }

    @Test func zeroSelectionRectFallsBackToCentered() {
        let origin = PanelGeometry.panelOrigin(panelSize: panelSize, selectionRect: .zero, visibleFrame: visible)
        let centered = PanelGeometry.centeredOrigin(panelSize: panelSize, visibleFrame: visible)
        #expect(origin == centered)
    }

    // MARK: - Anchor fallback chain

    @Test func anchorPrefersSelectionBounds() {
        let sel = CGRect(x: 100, y: 200, width: 80, height: 18)
        let el = CGRect(x: 0, y: 0, width: 400, height: 30)
        let anchor = PanelGeometry.anchorRect(selectionBounds: sel, elementBounds: el, mouseLocation: CGPoint(x: 5, y: 5))
        #expect(anchor == sel)
    }

    @Test func anchorFallsBackToSmallElementBounds() {
        let el = CGRect(x: 50, y: 60, width: 400, height: 30)
        let anchor = PanelGeometry.anchorRect(selectionBounds: nil, elementBounds: el, mouseLocation: CGPoint(x: 5, y: 5))
        #expect(anchor == el)
    }

    @Test func anchorSkipsOversizedElement() {
        // A whole web area / document view is not a useful anchor
        let el = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let mouse = CGPoint(x: 300, y: 400)
        let anchor = PanelGeometry.anchorRect(selectionBounds: nil, elementBounds: el, mouseLocation: mouse)
        #expect(anchor.midX == mouse.x + 0.5)
        #expect(anchor.height == 20)
    }

    @Test func anchorFallsBackToMouseWhenNothingElse() {
        let mouse = CGPoint(x: 640, y: 350)
        let anchor = PanelGeometry.anchorRect(selectionBounds: nil, elementBounds: nil, mouseLocation: mouse)
        #expect(anchor.origin.x == mouse.x)
        #expect(anchor.contains(CGPoint(x: mouse.x, y: mouse.y - 1)))
    }

    @Test func zeroSelectionBoundsUsesFallbacks() {
        let el = CGRect(x: 50, y: 60, width: 400, height: 30)
        let anchor = PanelGeometry.anchorRect(selectionBounds: .zero, elementBounds: el, mouseLocation: .zero)
        #expect(anchor == el)
    }
}
