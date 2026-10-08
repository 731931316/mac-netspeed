import Foundation

/// Contains only bounded smoke-test evidence, without interface names or machine identity.
struct SmokeReport: Codable, Sendable {
    /// States whether every required smoke check passed.
    let success: Bool
    /// Counts actual successful calls to the system counter reader.
    let realSampleCount: Int
    /// Counts all attempted reads, including failures.
    let samplingAttemptCount: Int
    /// Counts ticks delivered by the refresh scheduler.
    let scheduledRefreshCount: Int
    /// Records the tested interval in seconds.
    let refreshIntervalSeconds: Double
    /// Records the root menu item count after startup.
    let menuItemCount: Int
    /// Records the native rendered image width in points.
    let imageWidthPoints: Double
    /// Records the native rendered image height in points.
    let imageHeightPoints: Double
    /// Records whether the actual image contains visible glyph alpha.
    let imageHasVisiblePixels: Bool
    /// Confirms the expected application identity without returning arbitrary bundle text.
    let applicationName: String
    /// Records the inspected bundle version for release diagnostics.
    let applicationVersion: String
    /// Records one of the four mapped login states without personal system details.
    let loginItemStatus: String
    /// Records that smoke-test dependencies cannot mutate real system login items.
    let loginItemSupportsChanges: Bool
    /// Records elapsed monotonic time rather than a machine-local timestamp.
    let elapsedSeconds: Double
    /// Names independent checks so a failed report remains actionable.
    let checks: [String: Bool]

    /// Writes a deterministic JSON report to the explicitly requested destination.
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
