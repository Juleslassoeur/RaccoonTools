import AppKit

enum RaccoonIcon {
    static func menuBarIcon() -> NSImage {
        // Load the raccoon photo; AppIcon.icns as fallback so installs
        // without raccoon.jpg (old bottles) still get the raccoon.
        let searchPaths = [
            Bundle.main.resourcePath.map { "\($0)/raccoon.jpg" },
            Bundle.main.resourcePath.map { "\($0)/AppIcon.icns" },
        ]

        for path in searchPaths.compactMap({ $0 }) {
            if let original = NSImage(contentsOfFile: path) {
                return resizeForMenuBar(original)
            }
        }

        // Fallback: simple circle with "R"
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func resizeForMenuBar(_ original: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Round corners
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.addClip()

            // Crop to center square from original
            let origSize = original.size
            let side = min(origSize.width, origSize.height)
            let cropRect = NSRect(
                x: (origSize.width - side) / 2,
                y: (origSize.height - side) / 2,
                width: side,
                height: side
            )

            original.draw(in: rect, from: cropRect, operation: .sourceOver, fraction: 1.0)
            return true
        }
        // NOT a template — show the actual photo colors
        image.isTemplate = false
        return image
    }
}
