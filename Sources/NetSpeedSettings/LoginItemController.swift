import OSLog

/// 驱动设置界面的登录项状态，防止重复点击及显示未经系统确认的结果。
@MainActor
public final class LoginItemController {
    /// 读取状态并执行系统操作，或由测试提供 mock 服务。
    private let service: any LoginItemServicing
    /// 使用统一日志子系统记录控制器关键节点。
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "LoginItemController")
    /// 最近一次从服务读取的真实系统状态。
    public private(set) var status: LoginItemStatus
    /// 在整个异步更新期间阻止重复修改请求。
    public private(set) var isUpdating = false
    /// 显示经过处理的中文错误，永不直接显示框架原始错误。
    public private(set) var errorMessage: String?
    /// 让界面在主线程同步状态，无需耦合特定界面框架。
    public var onChange: (@MainActor () -> Void)?

    /// 创建控制器并直接读取服务当前状态，不进行注册或注销。
    public init(service: any LoginItemServicing) {
        self.service = service
        status = service.status
    }

    /// 返回当前服务是否允许设置变更。
    public var supportsChanges: Bool { service.supportsChanges }

    /// 重新读取真实状态，供窗口再次打开或系统设置返回后使用。
    public func refresh() {
        status = service.status
        onChange?()
    }

    /// 串行处理登录项请求，操作结束后始终读取真实状态再通知界面。
    public func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else {
            logger.debug("登录项正在更新，忽略重复请求")
            return
        }
        errorMessage = nil
        guard supportsChanges else {
            errorMessage = LoginItemServiceError.readOnly.errorDescription
            refresh()
            return
        }
        isUpdating = true
        onChange?()
        // 无论系统操作成功、失败或状态未更新，都以最新状态恢复界面。
        defer {
            status = service.status
            isUpdating = false
            onChange?()
        }
        do {
            try await service.setEnabled(enabled)
            logger.info("登录项设置请求已完成")
        } catch {
            if let safeError = error as? LoginItemServiceError {
                errorMessage = safeError.errorDescription
            } else {
                errorMessage = "无法更新登录时启动设置。请稍后重试，并检查系统登录项设置。"
            }
            logger.error("登录项设置请求失败，已重新读取系统状态")
        }
    }

    /// 根据当前服务能力打开系统设置，只读检查时不会触发系统 UI。
    public func openSystemSettings() {
        guard supportsChanges else {
            logger.debug("只读模式忽略系统设置入口")
            return
        }
        service.openSystemSettings()
    }
}
