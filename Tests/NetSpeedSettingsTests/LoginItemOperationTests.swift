@testable import NetSpeedSettings
import XCTest

/// 验证首次注册与幂等注销决策，纯逻辑不会修改本机登录项。
final class LoginItemOperationTests: XCTestCase {
    /// 启用覆盖四种真实状态；首次未知状态允许到达官方注册决策。
    func testEnableDecisionAcrossAllFourStatuses() throws {
        let expected: [(LoginItemStatus, LoginItemOperation)] = [
            (.notRegistered, .register),
            (.enabled, .none),
            (.requiresApproval, .none),
            (.unavailable, .register)
        ]
        for (status, operation) in expected {
            XCTAssertEqual(try LoginItemOperation.operation(enabled: true, status: status), operation)
        }
    }

    /// 关闭覆盖所有已知状态，已注册及待批准均注销，未注册保持幂等。
    func testDisableDecisionAcrossKnownStatuses() throws {
        let expected: [(LoginItemStatus, LoginItemOperation)] = [
            (.notRegistered, .none),
            (.enabled, .unregister),
            (.requiresApproval, .unregister)
        ]
        for (status, operation) in expected {
            XCTAssertEqual(try LoginItemOperation.operation(enabled: false, status: status), operation)
        }
    }

    /// 关闭未知状态必须明确拒绝，不伪称已注销，也不推测安装路径错误。
    func testDisableUnknownStatusRejectsWithoutClaimingSuccess() {
        XCTAssertThrowsError(try LoginItemOperation.operation(enabled: false, status: .unavailable)) { error in
            guard case LoginItemServiceError.unavailable = error else {
                return XCTFail("未知关闭状态应返回不可确认状态错误")
            }
            XCTAssertFalse(error.localizedDescription.contains("应用程序"))
        }
    }
}
