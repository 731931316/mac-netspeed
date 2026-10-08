import Foundation
import OSLog

/// 按接口计算相邻采样差值，防止网卡切换与计数重置产生尖峰。
public struct NetworkRateCalculator: Sendable {
    /// 记录异常时间与计数重置；日志不包含网络地址或计数内容。
    private static let logger = Logger(subsystem: "io.github.mac-netspeed", category: "RateCalculator")
    /// 上一次有效快照的单调时间。
    private var previousTimestamp: TimeInterval?
    /// 每个接口自己的累计计数基线。
    private var baselines: [String: InterfaceCounters] = [:]

    /// 创建尚未建立采样基线的计算器。
    public init() {}

    /// 消费快照并返回安全速率；首次出现的接口先建立基线。
    public mutating func consume(_ snapshot: NetworkSnapshot) -> TransferRate {
        // 使用字典避免重复接口被累加两次，并让消失接口自然退出基线。
        let current = snapshot.interfaces.reduce(into: [String: InterfaceCounters]()) { counters, interface in
            counters[interface.identifier] = interface
        }
        let names = current.keys.sorted()
        let zero = TransferRate(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, interfaceNames: names)

        guard snapshot.timestamp.isFinite, snapshot.timestamp >= 0 else {
            Self.logger.warning("采样时间无效，清空速率基线")
            reset()
            return zero
        }

        // 每次消费都更新基线；时间倒退或重复时下一次从新时间重新计算。
        defer {
            previousTimestamp = snapshot.timestamp
            baselines = current
        }
        guard let previousTimestamp else { return zero }
        let elapsed = snapshot.timestamp - previousTimestamp
        guard elapsed.isFinite, elapsed > 0 else {
            Self.logger.warning("采样时间未前进，重新建立速率基线")
            return zero
        }

        var received: Double = 0
        var sent: Double = 0
        for (identifier, counters) in current {
            guard let baseline = baselines[identifier] else { continue }
            // 任一方向回退都视为接口计数重置，整条接口重新建立基线。
            guard counters.receivedBytes >= baseline.receivedBytes,
                  counters.sentBytes >= baseline.sentBytes else {
                Self.logger.warning("接口累计计数回退，重新建立该接口基线")
                continue
            }
            // 先做 UInt64 差值再转浮点，避免大计数下丢失小增量。
            received += Double(counters.receivedBytes - baseline.receivedBytes)
            sent += Double(counters.sentBytes - baseline.sentBytes)
        }

        let download = received / elapsed
        let upload = sent / elapsed
        guard download.isFinite, upload.isFinite else {
            Self.logger.warning("采样间隔过小导致无效速率，本次返回零速率")
            return zero
        }
        return TransferRate(
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            interfaceNames: names
        )
    }

    /// 丢弃所有接口基线，供采样失败及睡眠恢复时重新开始计算。
    public mutating func reset() {
        previousTimestamp = nil
        baselines.removeAll(keepingCapacity: true)
    }
}
