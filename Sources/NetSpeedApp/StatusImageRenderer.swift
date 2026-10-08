import AppKit
import OSLog

/// Draws a compact two-line image through native AppKit text rendering.
@MainActor
enum StatusImageRenderer {
    /// Holds the display width steady while numeric values and units change.
    static let width: CGFloat = 72
    /// Fits both rows inside the standard macOS status-bar content height.
    static let height: CGFloat = 22
    /// Keeps glyphs clear of both horizontal image edges without excess whitespace.
    static let horizontalPadding: CGFloat = 4
    /// Records exceptional text fitting through the application's common log subsystem.
    private static let logger = Logger(subsystem: "io.github.mac-netspeed", category: "StatusImage")

    /// Renders upload above download, leaving system appearance to template styling.
    static func image(upload: String, download: String) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Start transparent; black glyph alpha is later styled by NSStatusBarButton.
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill(using: .copy)
        drawRow(rowText(direction: "↑", value: upload), y: 11)
        drawRow(rowText(direction: "↓", value: download), y: 0)
        image.isTemplate = true
        return image
    }

    /// Removes spaces only from the status image, preserving numbers, units, and state labels.
    static func rowText(direction: String, value: String) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        return NSAttributedString(string: direction + value.replacingOccurrences(of: " ", with: ""), attributes: attributes)
    }

    /// Fits unusually long rates inside the fixed width without dropping digits or units.
    private static func drawRow(_ row: NSAttributedString, y: CGFloat) {
        let availableWidth = width - horizontalPadding * 2
        let scale = min(1, availableWidth / max(row.size().width, 1))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Common rates retain the original font; only exceptionally long rows compress horizontally.
        let transform = NSAffineTransform()
        transform.translateX(by: horizontalPadding, yBy: y)
        transform.scaleX(by: scale, yBy: 1)
        transform.concat()
        row.draw(at: .zero)
        if scale < 1 {
            logger.debug("较长网速文案已适配固定菜单栏宽度")
        }
    }

    /// Checks rendered alpha rather than treating a correctly sized empty image as valid.
    static func hasVisiblePixels(_ image: NSImage) -> Bool {
        guard let representation = bitmapRepresentation(image) else { return false }
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0 {
                    return true
                }
            }
        }
        return false
    }

    /// Exports the same actual image used in the status button for optional visual review.
    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let representation = bitmapRepresentation(image),
              let data = representation.representation(using: .png, properties: [:]) else {
            throw StatusImageError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    /// Converts the AppKit drawing to a bitmap for bounded diagnostic inspection.
    private static func bitmapRepresentation(_ image: NSImage) -> NSBitmapImageRep? {
        guard let data = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: data)
    }
}

/// Identifies a rendering export failure without exposing the requested filesystem path.
enum StatusImageError: Error {
    /// AppKit could not produce bitmap data from the rendered status image.
    case encodingFailed
}
