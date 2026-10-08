import AppKit
@testable import NetSpeedApp
import NetSpeedCore
import XCTest

/// Verifies the approved width, truthful compact labels, and actual two-row glyph rendering.
final class StatusImageRendererTests: XCTestCase {
    /// Locks the requested 72-point width while preserving the standard two-line height.
    @MainActor
    func testFixedCompactDimensionsAndTemplateAppearance() {
        let image = StatusImageRenderer.image(upload: "1.2 KB/s", download: "12.3 MB/s")
        XCTAssertEqual(image.size, NSSize(width: 72, height: 22))
        XCTAssertTrue(image.isTemplate)
    }

    /// Compact rows retain both direction and explicit bytes-per-second units.
    @MainActor
    func testCompactLabelsPreserveNumbersAndUnits() {
        let fixtures: [(Double, String, String)] = [
            (0, "0 B/s", "0B/s"),
            (999.94, "999.9 B/s", "999.9B/s"),
            (999.99, "1.0 KB/s", "1.0KB/s"),
            (999_999.99, "1.0 MB/s", "1.0MB/s"),
            (12_340_000, "12.3 MB/s", "12.3MB/s"),
            (1_000_000_000_000, "1000.0 GB/s", "1000.0GB/s")
        ]
        for (value, expectedDetail, expectedCompact) in fixtures {
            let fullValue = RateFormatter.string(bytesPerSecond: value)
            XCTAssertEqual(fullValue, expectedDetail)
            XCTAssertEqual(StatusImageRenderer.rowText(direction: "↑", value: fullValue).string, "↑" + expectedCompact)
            XCTAssertEqual(StatusImageRenderer.rowText(direction: "↓", value: fullValue).string, "↓" + expectedCompact)
        }
    }

    /// Sampling, sleep, and unavailable states remain readable instead of becoming rates.
    @MainActor
    func testStateLabelsRemainIntact() {
        for state in ["采样中", "暂停", "不可用"] {
            XCTAssertEqual(StatusImageRenderer.rowText(direction: "↑", value: state).string, "↑" + state)
            XCTAssertEqual(StatusImageRenderer.rowText(direction: "↓", value: state).string, "↓" + state)
        }
    }

    /// The longest ordinary rates and the existing terabyte fixture fit without reducing the font.
    @MainActor
    func testLongRatesFitAtOriginalFontSize() {
        let availableWidth = StatusImageRenderer.width - StatusImageRenderer.horizontalPadding * 2
        for value in ["999.9 B/s", "999.9 KB/s", "999.9 MB/s", "999.9 GB/s", "1000.0 GB/s"] {
            for direction in ["↑", "↓"] {
                let row = StatusImageRenderer.rowText(direction: direction, value: value)
                let font = row.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                XCTAssertEqual(font?.pointSize, 9)
                XCTAssertLessThanOrEqual(row.size().width, availableWidth, value)
            }
        }
    }

    /// Checks real pixels in both rows and ensures even extreme rates retain edge padding.
    @MainActor
    func testRenderedRowsAndPaddingAcrossRateLengths() throws {
        for values in [("0 B/s", "12.3 MB/s"), ("999.9 MB/s", "1000.0 GB/s"), ("1000000.0 GB/s", "采样中")] {
            let image = StatusImageRenderer.image(upload: values.0, download: values.1)
            let data = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
            let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
            var upperRowHasPixels = false
            var lowerRowHasPixels = false
            var rightmostVisiblePoint: CGFloat = 0

            // Inspect the actual raster, including Retina output, rather than only its declared size.
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.01 else { continue }
                    let pointX = CGFloat(x) / scaleX
                    XCTAssertGreaterThanOrEqual(pointX, 3)
                    XCTAssertLessThan(pointX, 69)
                    rightmostVisiblePoint = max(rightmostVisiblePoint, pointX)
                    if CGFloat(y) / scaleY < 11 {
                        upperRowHasPixels = true
                    } else {
                        lowerRowHasPixels = true
                    }
                }
            }
            XCTAssertTrue(upperRowHasPixels)
            XCTAssertTrue(lowerRowHasPixels)
            if values.0 == "1000000.0 GB/s" {
                XCTAssertGreaterThan(rightmostVisiblePoint, 60, "Long rows must be fitted into the available width")
            }
        }
    }

    /// Distinguishes visible rendered content from a correctly sized but completely blank image.
    @MainActor
    func testVisiblePixelCheckRejectsBlankImage() {
        let blank = NSImage(size: NSSize(width: 72, height: 22))
        blank.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: blank.size).fill(using: .copy)
        blank.unlockFocus()
        XCTAssertFalse(StatusImageRenderer.hasVisiblePixels(blank))
        XCTAssertTrue(StatusImageRenderer.hasVisiblePixels(StatusImageRenderer.image(upload: "0 B/s", download: "0 B/s")))
    }
}
