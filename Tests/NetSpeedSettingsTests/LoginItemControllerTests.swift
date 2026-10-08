import Foundation
@testable import NetSpeedSettings
import XCTest

/// 验证主线程控制器行为，所有登录项修改均由内存 mock 完成。
@MainActor
final class LoginItemControllerTests: XCTestCase {
    /// 初始化仅读取实际状态，不擅自注册或修改任何状态。
    func testInitializesFromEachRealStatus() async {
        for status in [LoginItemStatus.notRegistered, .enabled, .requiresApproval, .unavailable] {
            let service = MockLoginItemService(status: status)
            let controller = LoginItemController(service: service)
            XCTAssertEqual(controller.status, status)
            XCTAssertFalse(controller.isUpdating)
            XCTAssertNil(controller.errorMessage)
            XCTAssertEqual(service.requests, [])
        }
    }

    /// 启用成功后使用服务实际结果，并在更新开始和结束通知界面。
    func testEnableRefreshesStatusAndNotifiesChanges() async {
        let service = MockLoginItemService(status: .notRegistered)
        service.resultingStatus = .enabled
        let controller = LoginItemController(service: service)
        var updatingStates: [Bool] = []
        controller.onChange = { updatingStates.append(controller.isUpdating) }
        await controller.setEnabled(true)
        XCTAssertEqual(service.requests, [true])
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertEqual(updatingStates, [true, false])
        XCTAssertFalse(controller.isUpdating)
        XCTAssertNil(controller.errorMessage)
    }

    /// 注销成功后刷新为未注册状态，不沿用操作前已启用状态。
    func testDisableRefreshesStatus() async {
        let service = MockLoginItemService(status: .enabled)
        service.resultingStatus = .notRegistered
        let controller = LoginItemController(service: service)
        await controller.setEnabled(false)
        XCTAssertEqual(service.requests, [false])
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertNil(controller.errorMessage)
    }

    /// 注册后需要用户批准时保留该状态，不凭期望值伪造 enabled。
    func testApprovalRemainsPendingAfterRegistration() async {
        let service = MockLoginItemService(status: .notRegistered)
        service.resultingStatus = .requiresApproval
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.status.isRegistered)
        XCTAssertNil(controller.errorMessage)
    }

    /// 服务实际未改变时控制器也不自行赋值为用户期望状态。
    func testDoesNotInventRequestedStatus() async {
        let service = MockLoginItemService(status: .notRegistered)
        service.resultingStatus = nil
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .notRegistered)
    }

    /// 原始框架错误可能包含路径，界面仅显示经过处理的中文信息。
    func testFailureRefreshesStateAndSanitizesError() async {
        let service = MockLoginItemService(status: .notRegistered)
        service.resultingStatus = .requiresApproval
        service.failure = ExampleFrameworkError()
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertFalse(controller.isUpdating)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.errorMessage?.contains("/private/example.app") ?? true)
        XCTAssertFalse(controller.errorMessage?.contains("框架内部内容") ?? true)
    }

    /// 可展示的安全错误保持对应含义，之后重试成功会清除历史错误。
    func testSafeFailureMessageClearsAfterSuccessfulRetry() async {
        let service = MockLoginItemService(status: .notRegistered)
        service.failure = LoginItemServiceError.unavailable
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(controller.errorMessage, LoginItemServiceError.unavailable.errorDescription)
        service.failure = nil
        service.resultingStatus = .enabled
        await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNil(controller.errorMessage)
    }

    /// 第一项操作暂停期间拒绝重复点击，防止交叉注册和注销。
    func testDuplicateRequestDoesNotStartConcurrentOperation() async {
        let service = MockLoginItemService(status: .notRegistered)
        service.suspendOperation = true
        service.resultingStatus = .enabled
        let controller = LoginItemController(service: service)
        let firstRequest = Task { @MainActor in await controller.setEnabled(true) }
        guard await waitUntilSuspended(service) else {
            service.suspendOperation = false
            service.completeSuspendedOperation()
            await firstRequest.value
            return
        }
        XCTAssertTrue(controller.isUpdating)
        await controller.setEnabled(false)
        XCTAssertEqual(service.requests, [true])
        service.completeSuspendedOperation()
        await firstRequest.value
        XCTAssertFalse(controller.isUpdating)
        XCTAssertEqual(controller.status, .enabled)
    }

    /// 显式刷新会读取在系统设置中发生的外部状态变更并通知界面。
    func testRefreshReadsExternalChange() async {
        let service = MockLoginItemService(status: .enabled)
        let controller = LoginItemController(service: service)
        var notifications = 0
        controller.onChange = { notifications += 1 }
        service.status = .requiresApproval
        controller.refresh()
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(service.requests, [])
    }

    /// 只读模式在控制器入口就拒绝修改，且会更新外部状态。
    func testReadOnlyControllerDoesNotInvokeMutation() async {
        let service = MockLoginItemService(status: .enabled, supportsChanges: false)
        let controller = LoginItemController(service: service)
        service.status = .notRegistered
        await controller.setEnabled(false)
        XCTAssertEqual(service.requests, [])
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertEqual(controller.errorMessage, LoginItemServiceError.readOnly.errorDescription)
        XCTAssertFalse(controller.supportsChanges)
        XCTAssertFalse(controller.isUpdating)
    }

    /// 系统设置入口只发送给正常服务，只读模式完全不调用替身入口。
    func testSystemSettingsEntryRespectsServiceCapability() async {
        let writable = MockLoginItemService(status: .requiresApproval)
        LoginItemController(service: writable).openSystemSettings()
        XCTAssertEqual(writable.openSettingsCount, 1)
        let readOnly = MockLoginItemService(status: .requiresApproval, supportsChanges: false)
        LoginItemController(service: readOnly).openSystemSettings()
        XCTAssertEqual(readOnly.openSettingsCount, 0)
    }

    /// 让首项主线程任务推进到可控暂停点，避免依赖固定等待时间。
    private func waitUntilSuspended(_ service: MockLoginItemService) async -> Bool {
        for _ in 0..<1_000 {
            if service.hasSuspendedOperation { return true }
            await Task.yield()
        }
        XCTFail("mock 操作未进入暂停点")
        return false
    }
}

/// 为设置测试提供纯内存状态及可控异步暂停点，不访问 ServiceManagement。
@MainActor
private final class MockLoginItemService: LoginItemServicing {
    /// 测试可主动修改的模拟系统状态。
    var status: LoginItemStatus
    /// 指定替身是否允许修改，供只读控制器测试使用。
    let supportsChanges: Bool
    /// 记录控制器发出的启用或注销请求。
    private(set) var requests: [Bool] = []
    /// 记录系统设置入口被调用次数，不实际打开任何窗口。
    private(set) var openSettingsCount = 0
    /// 指定操作完成后产生的实际状态，nil 表示不改变状态。
    var resultingStatus: LoginItemStatus?
    /// 指定操作应抛出的错误，模拟框架失败及安全错误。
    var failure: (any Error)?
    /// 控制操作是否等待测试显式完成，供重复点击验证使用。
    var suspendOperation = false
    /// 保留模拟操作的继续执行点，完全由测试生命周期管理。
    private var continuation: CheckedContinuation<Void, Never>?

    /// 创建不访问本机登录项的服务替身。
    init(status: LoginItemStatus, supportsChanges: Bool = true) {
        self.status = status
        self.supportsChanges = supportsChanges
    }

    /// 表示异步模拟操作是否已进入暂停点。
    var hasSuspendedOperation: Bool { continuation != nil }

    /// 记录请求并应用模拟结果或错误，不调用任何系统注册 API。
    func setEnabled(_ enabled: Bool) async throws {
        requests.append(enabled)
        if suspendOperation {
            await withCheckedContinuation { continuation = $0 }
        }
        if let resultingStatus { status = resultingStatus }
        if let failure { throw failure }
    }

    /// 记录入口被调用，不打开系统设置。
    func openSystemSettings() {
        openSettingsCount += 1
    }

    /// 完成暂停的模拟操作，并清除继续执行点以防重复恢复。
    func completeSuspendedOperation() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

/// 模拟包含内部路径的框架错误，验证它不会直接进入用户提示。
private struct ExampleFrameworkError: LocalizedError {
    /// 返回仅用于测试的示例内部内容。
    var errorDescription: String? { "框架内部内容 /private/example.app" }
}
