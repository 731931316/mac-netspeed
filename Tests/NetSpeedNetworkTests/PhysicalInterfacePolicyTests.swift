import SystemConfiguration
@testable import NetSpeedNetwork
import XCTest

/// 验证物理接口统计口径，避免 VPN 与虚拟网卡双计。
final class PhysicalInterfacePolicyTests: XCTestCase {
    /// Wi-Fi 名称不固定为 en0，依系统类型识别。
    func testWiFiWithArbitraryBSDName() {
        XCTAssertTrue(PhysicalInterfacePolicy.allows(interfaceType: kSCNetworkInterfaceTypeIEEE80211 as String, bsdName: "en7"))
    }

    /// 以太网接口可使用任意系统分配的 en* 名称。
    func testEthernetWithArbitraryBSDName() {
        XCTAssertTrue(PhysicalInterfacePolicy.allows(interfaceType: kSCNetworkInterfaceTypeEthernet as String, bsdName: "en0"))
    }

    /// 不将 VPN 与未知类型接口纳入物理计数。
    func testRejectsVPNAndUnknownTypes() {
        XCTAssertFalse(PhysicalInterfacePolicy.allows(interfaceType: kSCNetworkInterfaceTypeIPSec as String, bsdName: "utun4"))
        XCTAssertFalse(PhysicalInterfacePolicy.allows(interfaceType: "Unknown", bsdName: "en0"))
    }

    /// 空名称和本地协作、回环、桥接及隧道接口始终排除。
    func testRejectsVirtualAndEmptyNames() {
        for name in ["", "lo0", "utun0", "awdl0", "llw0", "bridge0"] {
            XCTAssertFalse(PhysicalInterfacePolicy.allows(interfaceType: kSCNetworkInterfaceTypeEthernet as String, bsdName: name))
        }
    }
}
