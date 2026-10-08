import ServiceManagement
@testable import NetSpeedSettings
import XCTest

/// 验证官方服务状态的映射及用户可见语义，不操作真实登录项。
final class LoginItemStatusTests: XCTestCase {
    /// 系统的四种状态分别映射，无法找到服务不得假装未注册。
    func testMapsAllSystemStatuses() {
        XCTAssertEqual(LoginItemStatus.from(.notRegistered), .notRegistered)
        XCTAssertEqual(LoginItemStatus.from(.enabled), .enabled)
        XCTAssertEqual(LoginItemStatus.from(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItemStatus.from(.notFound), .unavailable)
    }

    /// 待批准已经注册，但不可用及未注册都不能算已注册。
    func testRegistrationFlags() {
        XCTAssertFalse(LoginItemStatus.notRegistered.isRegistered)
        XCTAssertTrue(LoginItemStatus.enabled.isRegistered)
        XCTAssertTrue(LoginItemStatus.requiresApproval.isRegistered)
        XCTAssertFalse(LoginItemStatus.unavailable.isRegistered)
    }

    /// 状态文案区分登录时启动成功、待批准及不可用。
    func testChineseDescriptionsKeepApprovalDistinct() {
        XCTAssertEqual(LoginItemStatus.notRegistered.description, "未开启登录时启动")
        XCTAssertEqual(LoginItemStatus.enabled.description, "已开启登录时启动")
        XCTAssertEqual(LoginItemStatus.requiresApproval.description, "已注册，等待系统批准")
        XCTAssertEqual(LoginItemStatus.unavailable.description, "登录项服务不可用")
    }
}
