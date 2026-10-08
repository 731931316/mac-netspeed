import Darwin
import Foundation
import NetSpeedCore
import OSLog
import SystemConfiguration

/// 读取活跃物理 Wi-Fi 及以太网接口的原生 64 位计数，不产生测速流量。
public struct SystemNetworkReader: Sendable {
    /// 记录读取异常及采样关键分支，不包含地址或其他网络身份信息。
    private static let logger = Logger(subsystem: "io.github.mac-netspeed", category: "NetworkReader")
    /// 防止异常系统返回值触发无界分配的快照大小上限。
    private static let maximumSnapshotSize = 16 * 1_024 * 1_024
    /// 允许查询与读取期间发生接口数量变化时有限重试。
    private static let maximumReadAttempts = 3

    /// 创建可在串行队列或 actor 内使用的网络采样器。
    public init() {}

    /// 返回当前物理接口计数及单调时间；计数包含局域网和 VPN 承载流量。
    public mutating func readSnapshot() throws -> NetworkSnapshot {
        do {
            // 每次刷新系统接口类型，及时识别热插拔设备及 Wi-Fi/有线切换。
            let eligibleNames = try physicalInterfaceNames()
            let data = try routingData()
            let timestamp = ProcessInfo.processInfo.systemUptime
            let records = try RouteMessageDecoder.decode(data)
            var counters: [InterfaceCounters] = []
            for record in records {
                guard record.isActive,
                      let name = interfaceName(index: record.index),
                      eligibleNames.contains(name) else { continue }
                counters.append(InterfaceCounters(
                    identifier: name,
                    receivedBytes: record.receivedBytes,
                    sentBytes: record.sentBytes
                ))
            }
            Self.logger.debug("系统计数采样完成，活跃物理接口数：\(counters.count)")
            return NetworkSnapshot(timestamp: timestamp, interfaces: counters.sorted { $0.identifier < $1.identifier })
        } catch {
            Self.logger.error("系统计数采样失败：\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// 查询系统配置中的物理 Wi-Fi 与以太网 BSD 名称。
    private func physicalInterfaceNames() throws -> Set<String> {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            throw NetworkReadError.interfaceCatalogUnavailable
        }
        var names: Set<String> = []
        for interface in interfaces {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  PhysicalInterfacePolicy.allows(interfaceType: type, bsdName: name) else { continue }
            names.insert(name)
        }
        return names
    }

    /// 使用 NET_RT_IFLIST2 获取含 if_data64 的路由消息快照。
    private func routingData() throws -> Data {
        for attempt in 0..<Self.maximumReadAttempts {
            var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
            var requestedSize = 0
            let queryResult = mib.withUnsafeMutableBufferPointer { pointer in
                sysctl(pointer.baseAddress, u_int(pointer.count), nil, &requestedSize, nil, 0)
            }
            guard queryResult == 0 else {
                throw NetworkReadError.systemCallFailed(code: errno)
            }
            guard requestedSize >= 0, requestedSize <= Self.maximumSnapshotSize else {
                throw NetworkReadError.invalidDataSize
            }
            if requestedSize == 0 { return Data() }

            var data = Data(count: requestedSize)
            var actualSize = requestedSize
            let readResult = data.withUnsafeMutableBytes { bytes in
                mib.withUnsafeMutableBufferPointer { pointer in
                    sysctl(pointer.baseAddress, u_int(pointer.count), bytes.baseAddress, &actualSize, nil, 0)
                }
            }
            if readResult == 0 {
                guard actualSize >= 0, actualSize <= requestedSize else {
                    throw NetworkReadError.invalidDataSize
                }
                // 接口消失时有效快照可能缩短，只解析系统实际返回的字节。
                data.count = actualSize
                return data
            }
            let failureCode = errno
            if failureCode == ENOMEM, attempt < Self.maximumReadAttempts - 1 {
                Self.logger.debug("接口快照大小发生变化，重新查询缓冲区大小")
                continue
            }
            throw NetworkReadError.systemCallFailed(code: failureCode)
        }
        throw NetworkReadError.systemCallFailed(code: ENOMEM)
    }

    /// 将有效接口索引解析为当前 BSD 名称，已消失的接口返回 nil。
    private func interfaceName(index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        let resolved = buffer.withUnsafeMutableBufferPointer { pointer in
            if_indextoname(UInt32(index), pointer.baseAddress) != nil
        }
        guard resolved else {
            Self.logger.debug("接口在采样期间消失，跳过该条计数")
            return nil
        }
        return buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
    }
}
