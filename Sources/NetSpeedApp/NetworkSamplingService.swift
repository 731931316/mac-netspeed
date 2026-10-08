import Foundation
import NetSpeedCore
import NetSpeedNetwork
import OSLog

/// Carries sampling state without sending mutable system objects to the UI actor.
enum SamplingOutcome: Sendable {
    /// The first successful snapshot establishes the next interval's baseline.
    case establishingBaseline(TransferRate)
    /// A subsequent successful snapshot produced an interval rate.
    case available(TransferRate)
    /// A failed read cannot be displayed as a measured zero.
    case unavailable
}

/// Serializes the platform reader and rate calculator away from the main actor.
actor NetworkSamplingService {
    /// Reads byte counters through the system's public networking interfaces.
    private var reader = SystemNetworkReader()
    /// Maintains the previous successful snapshot for difference calculations.
    private var calculator = NetworkRateCalculator()
    /// Separates the first baseline read from a complete measurement interval.
    private var hasBaseline = false
    /// Records diagnostic events through the common application subsystem.
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "Sampling")

    /// Reads one real snapshot and resets continuity after failures.
    func sample() -> SamplingOutcome {
        do {
            let snapshot = try reader.readSnapshot()
            let rate = calculator.consume(snapshot)
            if !hasBaseline {
                hasBaseline = true
                logger.debug("已建立网络采样基线")
                return .establishingBaseline(rate)
            }
            return .available(rate)
        } catch {
            // An unreadable interval must never reuse old rates or pretend to be idle.
            calculator.reset()
            hasBaseline = false
            logger.error("读取网络计数失败，已清除采样基线")
            return .unavailable
        }
    }

    /// Discards pre-sleep counters so wake-up cannot average over the sleep interval.
    func reset() {
        reader = SystemNetworkReader()
        calculator.reset()
        hasBaseline = false
        logger.debug("已重置网络采样状态")
    }
}
