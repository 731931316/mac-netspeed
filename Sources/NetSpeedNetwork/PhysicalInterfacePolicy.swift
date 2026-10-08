import Foundation
import SystemConfiguration

/// 确定当前版本统计的物理接口类型，避免隧道与承载网卡重复计数。
enum PhysicalInterfacePolicy {
    /// 根据系统接口类型判断 Wi-Fi 或以太网，不假定特定 en* 名称。
    static func allows(interfaceType: String, bsdName: String) -> Bool {
        guard !bsdName.isEmpty,
              interfaceType == (kSCNetworkInterfaceTypeEthernet as String)
                || interfaceType == (kSCNetworkInterfaceTypeIEEE80211 as String) else {
            return false
        }
        // 防御性排除本地协作、回环、桥接及隧道接口。
        return bsdName != "lo0"
            && !bsdName.hasPrefix("utun")
            && !bsdName.hasPrefix("awdl")
            && !bsdName.hasPrefix("llw")
            && !bsdName.hasPrefix("bridge")
    }
}
