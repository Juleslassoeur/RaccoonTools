import Testing
import AppKit
@testable import RaccoonTools

@Suite struct PaletteColorTests {

    private func expectRGB(_ color: NSColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            Issue.record("color not convertible to sRGB", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(srgb.redComponent - r) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(srgb.greenComponent - g) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(srgb.blueComponent - b) < 0.001, sourceLocation: sourceLocation)
    }

    // MARK: - PaletteColor.color hex parsing

    @Test func validHexWithHash() {
        let c = PaletteColor(hex: "#AABBCC", name: "n", role: "r").color
        expectRGB(c, 0xAA / 255.0, 0xBB / 255.0, 0xCC / 255.0)
    }

    @Test func validHexWithoutHash() {
        let c = PaletteColor(hex: "FF7F00", name: "n", role: "r").color
        expectRGB(c, 1.0, 0x7F / 255.0, 0.0)
    }

    @Test func lowercaseHexAndSurroundingWhitespace() {
        let c = PaletteColor(hex: "  #aabbcc ", name: "n", role: "r").color
        expectRGB(c, 0xAA / 255.0, 0xBB / 255.0, 0xCC / 255.0)
    }

    @Test func invalidLengthFallsBackToGray() {
        #expect(PaletteColor(hex: "#ABC", name: "n", role: "r").color == NSColor.gray)
        #expect(PaletteColor(hex: "#AABBCCDD", name: "n", role: "r").color == NSColor.gray)
        #expect(PaletteColor(hex: "", name: "n", role: "r").color == NSColor.gray)
    }

    @Test func invalidCharactersFallBackToGray() {
        #expect(PaletteColor(hex: "#GGHHII", name: "n", role: "r").color == NSColor.gray)
        #expect(PaletteColor(hex: "not a color", name: "n", role: "r").color == NSColor.gray)
    }

    // MARK: - PickedColor hex formatting

    @Test func pickedColorHexFromNSColor() {
        // Components exactly representable in binary to avoid FP rounding surprises
        let picked = PickedColor(nsColor: NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0))
        #expect(picked.hex == "#FF7F00")  // Int() truncates 127.5 to 127
        #expect(picked.r == 255)
        #expect(picked.g == 127)
        #expect(picked.b == 0)
        #expect(picked.cssRGB == "rgb(255, 127, 0)")
    }

    @Test func pickedColorBlackAndWhite() {
        #expect(PickedColor(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)).hex == "#000000")
        #expect(PickedColor(nsColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)).hex == "#FFFFFF")
    }

    @Test func pickedColorRoundTripsThroughPaletteColor() {
        let picked = PickedColor(nsColor: NSColor(srgbRed: 0.25, green: 0.75, blue: 1.0, alpha: 1.0))
        let parsed = PaletteColor(hex: picked.hex, name: "n", role: "r").color
        expectRGB(parsed, CGFloat(picked.r) / 255.0, CGFloat(picked.g) / 255.0, CGFloat(picked.b) / 255.0)
    }
}
