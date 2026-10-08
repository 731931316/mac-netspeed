import Foundation

/// 定义登录项控制边界，允许单元测试及冒烟流程注入安全替身。
@MainActor
public protocol LoginItemServicing: AnyObject {
    /// 返回服务当前的真实状态，调用方不得用期望状态替代它。
    var status: LoginItemStatus { get }
    /// 返回是否允许修改系统登录项及打开相关系统设置。
    var supportsChanges: Bool { get }

    /// 注册或注销登录项，失败时保留系统状态并抛出错误。
    func setEnabled(_ enabled: Bool) async throws

    /// 在获得界面操作后打开系统登录项设置。
    func openSystemSettings()
}

/// 提供不含原始错误内容、路径或身份信息的登录项错误。
public enum LoginItemServiceError: Error, LocalizedError, Sendable {
    /// 当前服务仅用于只读检查，不允许变更系统设置。
    case readOnly
    /// 系统无法识别当前应用对应的登录项服务。
    case unavailable
    /// 系统操作返回后，实际状态与请求仍不一致。
    case stateNotUpdated

    /// 返回可显示的中文错误；外部框架错误由控制器另外转换。
    public var errorDescription: String? {
        switch self {
        case .readOnly: "当前处于只读检查模式，无法修改登录时启动设置。"
        case .unavailable: "系统暂时无法确认登录项状态。请稍后重试，并检查系统登录项设置。"
        case .stateNotUpdated: "系统尚未完成登录项设置更新，请稍后重试。"
        }
    }
}
