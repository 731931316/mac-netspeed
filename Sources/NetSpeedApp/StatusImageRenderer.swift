import AppKit

/// Draws a compact two-line image through native AppKit text rendering.
@MainActor
enum StatusImageRenderer {
    /// Holds the display width steady while numeric values and units change.
    static let width: CGFloat = 112
    /// Fits both rows inside the standard macOS status-bar content height.
    static let height: CGFloat = 22

    /// Renders upload above download, leaving system appearance to template styling.
    static func image(upload: String, download: String) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Start transparent; black glyph alpha is later styled by NSStatusBarButton.
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill(using: .copy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: "↑ \(upload)", attributes: attributes)
            .draw(at: NSPoint(x: 6, y: 11))
        NSAttributedString(string: "↓ \(download)", attributes: attributes)
            .draw(at: NSPoint(x: 6, y: 0))
        image.isTemplate = true
        return image
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
