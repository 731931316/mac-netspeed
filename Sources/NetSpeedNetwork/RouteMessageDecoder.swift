import Darwin
import Foundation

/// 保存一条已校验的原生 64 位接口计数记录。
struct RouteInterfaceRecord: Sendable, Equatable {
    /// 系统分配的接口索引。
    let index: UInt16
    /// 接口当前的 IFF_* 状态标记。
    let flags: Int32
    /// 原生 64 位累计接收字节数。
    let receivedBytes: UInt64
    /// 原生 64 位累计发送字节数。
    let sentBytes: UInt64

    /// 接口同时处于管理启用与驱动运行状态时才参与统计。
    var isActive: Bool {
        let requiredFlags = Int32(IFF_UP | IFF_RUNNING)
        return flags & requiredFlags == requiredFlags
    }
}

/// 解析 NET_RT_IFLIST2 返回的消息序列，逐条验证长度、版本及索引。
enum RouteMessageDecoder {
    /// 路由消息共用的长度、版本及类型字段占用字节数。
    private static let prefixSize = 4

    /// 读取接口消息，跳过结构合法的其他类型消息。
    static func decode(_ data: Data) throws -> [RouteInterfaceRecord] {
        try data.withUnsafeBytes { bytes in
            var records: [RouteInterfaceRecord] = []
            var seenIndices: Set<UInt16> = []
            var offset = 0
            while offset < bytes.count {
                // 必须先验证共用头部，再读取不保证自然对齐的系统字节。
                guard bytes.count - offset >= prefixSize else {
                    throw NetworkReadError.malformedMessage(offset: offset)
                }
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                let version = bytes.loadUnaligned(fromByteOffset: offset + 2, as: UInt8.self)
                let type = bytes.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
                guard length >= prefixSize, length <= bytes.count - offset else {
                    throw NetworkReadError.malformedMessage(offset: offset)
                }
                guard version == UInt8(RTM_VERSION) else {
                    throw NetworkReadError.unsupportedVersion(version: version)
                }

                if type == UInt8(RTM_IFINFO2) {
                    // 仅完整的 if_msghdr2 可读取 if_data64，禁止将旧结构强转。
                    guard length >= MemoryLayout<if_msghdr2>.size else {
                        throw NetworkReadError.malformedMessage(offset: offset)
                    }
                    let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    guard message.ifm_index > 0 else {
                        throw NetworkReadError.malformedMessage(offset: offset)
                    }
                    guard seenIndices.insert(message.ifm_index).inserted else {
                        throw NetworkReadError.duplicateInterface(index: message.ifm_index)
                    }
                    records.append(RouteInterfaceRecord(
                        index: message.ifm_index,
                        flags: message.ifm_flags,
                        receivedBytes: message.ifm_data.ifi_ibytes,
                        sentBytes: message.ifm_data.ifi_obytes
                    ))
                }
                // 使用已经校验的消息长度前进，避免零长度死循环及越界。
                offset += length
            }
            return records
        }
    }
}
