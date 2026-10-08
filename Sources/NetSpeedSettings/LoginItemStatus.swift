import ServiceManagement

/// 表示系统登录项的真实状态，区分已注册与用户尚未批准。
public enum LoginItemStatus: Sendable, Equatable {
    /// 应用尚未注册为登录项，或已经注销。
    case notRegistered
    /// 应用已获批准，可以在用户登录时启动。
    case enabled
    /// 应用已注册，但需要用户在系统设置中允许启动。
    case requiresApproval
    /// 系统无法找到对应服务，当前状态不可用。
    case unavailable

    /// 返回是否已注册；待批准的服务也已经完成注册。
    public var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }

    /// 返回适合直接显示的中文状态，不承诺尚未批准的启动行为。
    public var description: String {
        switch self {
        case .notRegistered: "未开启登录时启动"
        case .enabled: "已开启登录时启动"
        case .requiresApproval: "已注册，等待系统批准"
        case .unavailable: "登录项服务不可用"
        }
    }

    /// 将 Apple ServiceManagement 的状态映射为应用使用的四种状态。
    static func from(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
}
