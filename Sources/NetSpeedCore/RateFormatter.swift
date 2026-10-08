import Foundation

/// 使用十进制单位格式化网速，保持菜单栏文案简洁且不受系统区域影响。
public enum RateFormatter {
    /// 根据速率大小选择的十进制单位。
    private static let units = ["B/s", "KB/s", "MB/s", "GB/s"]

    /// 格式化每秒字节数；负值、非有限值及零值统一显示为 0 B/s。
    public static func string(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 B/s" }
        var value = bytesPerSecond
        var unitIndex = 0
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        // 接近单位边界时随一位小数的舍入提升单位，避免显示 1000.0 KB/s。
        if (value * 10).rounded() >= 10_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        return String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), value, units[unitIndex])
    }
}
