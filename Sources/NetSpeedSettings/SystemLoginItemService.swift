import OSLog
import ServiceManagement

/// 通过 macOS 13 起提供的主应用登录项服务管理登录时启动。
@MainActor
public final class SystemLoginItemService: LoginItemServicing {
    /// 使用项目统一日志子系统，避免记录原始系统错误或路径。
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "LoginItem")

    /// 创建只在用户明确操作设置时才修改登录项的服务。
    public init() {}

    /// 每次直接读取 ServiceManagement，反映系统设置中的外部变更。
    public var status: LoginItemStatus {
        LoginItemStatus.from(SMAppService.mainApp.status)
    }

    /// 正常应用服务允许用户主动修改登录项。
    public var supportsChanges: Bool { true }

    /// 根据真实状态执行幂等注册或异步注销，并校验操作后的实际状态。
    public func setEnabled(_ enabled: Bool) async throws {
        let operation = try LoginItemOperation.operation(enabled: enabled, status: status)
        do {
            switch operation {
            case .none:
                logger.debug("登录项已处于请求的注册状态，无需重复操作")
                return
            case .register:
                // 首次未知状态也必须允许官方 API 返回真实注册结果。
                try SMAppService.mainApp.register()
            case .unregister:
                try await SMAppService.mainApp.unregister()
            }
            let updated = status
            guard enabled ? updated.isRegistered : updated == .notRegistered else {
                throw LoginItemServiceError.stateNotUpdated
            }
            logger.info("已更新登录项注册状态")
        } catch {
            logger.error("系统登录项更新失败")
            throw error
        }
    }

    /// 仅供用户点击设置入口后调用，打开系统登录项设置。
    public func openSystemSettings() {
        logger.info("用户请求打开系统登录项设置")
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// 为冒烟测试提供真实状态读取，同时明确禁止任何系统设置操作。
@MainActor
public final class ReadOnlyLoginItemService: LoginItemServicing {
    /// 只记录只读检查事件，不记录服务状态中的机器信息。
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "LoginItem")

    /// 创建不注册、不注销、不打开系统设置的检查服务。
    public init() {}

    /// 读取真实主应用登录项状态，读取本身不会修改系统配置。
    public var status: LoginItemStatus {
        LoginItemStatus.from(SMAppService.mainApp.status)
    }

    /// 禁止界面或检查流程请求登录项修改。
    public var supportsChanges: Bool { false }

    /// 无论期望值如何都明确拒绝操作，不调用任何注册或注销 API。
    public func setEnabled(_ enabled: Bool) async throws {
        logger.debug("只读服务拒绝登录项修改请求")
        throw LoginItemServiceError.readOnly
    }

    /// 冒烟流程不得打开系统设置，因此只记录被拒绝的只读请求。
    public func openSystemSettings() {
        logger.debug("只读服务拒绝打开系统设置")
    }
}
