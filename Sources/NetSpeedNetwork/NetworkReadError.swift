import Foundation

/// 表示系统网络计数读取或路由消息校验失败。
public enum NetworkReadError: Error, LocalizedError, Sendable, Equatable {
    /// sysctl 失败，仅保留不含敏感内容的系统错误码。
    case systemCallFailed(code: Int32)
    /// 系统接口目录无法读取。
    case interfaceCatalogUnavailable
    /// 路由快照超过合理缓冲区上限。
    case invalidDataSize
    /// 路由消息长度、索引或结构边界无效。
    case malformedMessage(offset: Int)
    /// 路由消息版本与本机 SDK 契约不符。
    case unsupportedVersion(version: UInt8)
    /// 快照包含同一接口的重复计数记录。
    case duplicateInterface(index: UInt16)

    /// 提供可直接显示给用户的读取错误说明。
    public var errorDescription: String? {
        switch self {
        case .systemCallFailed(let code):
            return "无法读取系统网络计数（错误码 \(code)）。"
        case .interfaceCatalogUnavailable:
            return "无法读取系统网络接口目录。"
        case .invalidDataSize:
            return "系统网络计数快照大小异常。"
        case .malformedMessage:
            return "系统网络计数消息结构异常。"
        case .unsupportedVersion:
            return "系统网络计数消息版本不兼容。"
        case .duplicateInterface:
            return "系统网络计数包含重复接口。"
        }
    }
}
