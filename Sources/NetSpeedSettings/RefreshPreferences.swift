import Foundation
import OSLog

/// 封装菜单与设置窗口共同使用的刷新偏好，兼容已有偏好键。
@MainActor
public final class RefreshPreferences {
    /// 当前版本允许的刷新周期，单位为秒。
    public static let supportedIntervals: [TimeInterval] = [0.5, 1, 2]
    /// 沿用既有版本的偏好键，不进行迁移或覆盖其他配置。
    private static let preferenceKey = "refreshIntervalSeconds"
    /// 正常应用使用标准偏好，单元测试注入隔离的偏好域。
    private let defaults: UserDefaults
    /// 使用统一日志子系统记录非法偏好及明确的修改操作。
    private let logger = Logger(subsystem: "io.github.mac-netspeed", category: "RefreshPreferences")

    /// 创建共享偏好对象，读取不会写回或删除现有配置。
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读取有效周期；缺失、错误类型、非有限及未支持值均回退为一秒。
    public var interval: TimeInterval {
        guard let stored = defaults.object(forKey: Self.preferenceKey) else { return 1 }
        guard let number = stored as? NSNumber,
              number.doubleValue.isFinite,
              Self.supportedIntervals.contains(number.doubleValue) else {
            logger.warning("刷新间隔偏好无效，使用默认 1 秒")
            return 1
        }
        return number.doubleValue
    }

    /// 保存受支持的有限周期，非法请求保持原偏好并返回 false。
    @discardableResult
    public func setInterval(_ value: TimeInterval) -> Bool {
        guard value.isFinite, Self.supportedIntervals.contains(value) else {
            logger.warning("拒绝不支持的刷新间隔设置")
            return false
        }
        defaults.set(value, forKey: Self.preferenceKey)
        logger.info("已保存网速刷新间隔")
        return true
    }
}
