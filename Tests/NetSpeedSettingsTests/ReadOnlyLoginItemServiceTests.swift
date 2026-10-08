import ServiceManagement
@testable import NetSpeedSettings
import XCTest

/// 验证冒烟专用服务仅读取系统状态，修改入口始终明确拒绝。
@MainActor
final class ReadOnlyLoginItemServiceTests: XCTestCase {
    /// 只读服务直接映射当前系统状态，不承诺允许任何修改。
    func testReadsActualStatusWithoutEnablingChanges() async {
        let service = ReadOnlyLoginItemService()
        XCTAssertEqual(service.status, LoginItemStatus.from(SMAppService.mainApp.status))
        XCTAssertFalse(service.supportsChanges)
    }

    /// 开启和关闭请求均抛出只读错误，不执行系统注册或注销。
    func testRejectsBothMutationRequests() async {
        let service = ReadOnlyLoginItemService()
        for enabled in [true, false] {
            do {
                try await service.setEnabled(enabled)
                XCTFail("只读服务不应接受登录项修改请求")
            } catch {
                guard case LoginItemServiceError.readOnly = error else {
                    return XCTFail("只读服务应返回明确的只读错误")
                }
            }
        }
    }
}
