import Foundation

/// 保存单个网络接口的原生 64 位累计收发字节数。
public struct InterfaceCounters: Sendable, Equatable {
    /// 接口的 BSD 标识，用于维护独立采样基线。
    public let identifier: String
    /// 接口累计接收字节数。
    public let receivedBytes: UInt64
    /// 接口累计发送字节数。
    public let sentBytes: UInt64

    /// 创建接口计数，保留系统提供的 64 位精度。
    public init(identifier: String, receivedBytes: UInt64, sentBytes: UInt64) {
        self.identifier = identifier
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

/// 保存同一次采样的单调时间及各接口累计计数。
public struct NetworkSnapshot: Sendable, Equatable {
    /// 从系统启动起计算的单调时间，单位为秒。
    public let timestamp: TimeInterval
    /// 当前参与统计的物理接口计数。
    public let interfaces: [InterfaceCounters]

    /// 创建用于计算相邻采样差值的快照。
    public init(timestamp: TimeInterval, interfaces: [InterfaceCounters]) {
        self.timestamp = timestamp
        self.interfaces = interfaces
    }
}

/// 表示参与统计接口的总上传与下载速率。
public struct TransferRate: Sendable, Equatable {
    /// 总接收速率，单位为字节每秒。
    public let downloadBytesPerSecond: Double
    /// 总发送速率，单位为字节每秒。
    public let uploadBytesPerSecond: Double
    /// 本次快照中的接口标识，按名称排序。
    public let interfaceNames: [String]

    /// 创建可直接用于菜单栏展示的速率结果。
    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double, interfaceNames: [String]) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.interfaceNames = interfaceNames
    }
}
