/// 将真实查询状态与用户请求转为纯操作决策，不调用任何系统 API。
enum LoginItemOperation: Sendable, Equatable {
    /// 已处于期望注册状态，不重复注册或注销。
    case none
    /// 用户明确请求启用，由官方注册 API 判定是否能够注册。
    case register
    /// 已知服务已经注册，用户明确请求注销。
    case unregister

    /// 保留首次未知状态的注册机会，关闭未知状态时拒绝伪称已注销。
    static func operation(enabled: Bool, status: LoginItemStatus) throws -> LoginItemOperation {
        if enabled {
            // 首次查询未找到服务不能证明注册不可行，交由 register 返回结果。
            return status.isRegistered ? .none : .register
        }
        switch status {
        case .notRegistered: return .none
        case .enabled, .requiresApproval: return .unregister
        case .unavailable: throw LoginItemServiceError.unavailable
        }
    }
}
