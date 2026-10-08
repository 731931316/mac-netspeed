import Foundation
@testable import NetSpeedSettings
import XCTest

/// 在独立随机偏好域中验证刷新设置，不读取或修改本机应用偏好。
@MainActor
final class RefreshPreferencesTests: XCTestCase {
    /// 没有持久设置时默认为一秒，支持周期与既有版本一致。
    func testDefaultIntervalAndSupportedChoices() async throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertEqual(RefreshPreferences(defaults: defaults).interval, 1)
        XCTAssertEqual(RefreshPreferences.supportedIntervals, [0.5, 1, 2])
    }

    /// 所有合法周期都使用原来的偏好键持久化，并能由另一个实例读回。
    func testPersistsSupportedIntervalsUsingExistingKey() async throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = RefreshPreferences(defaults: defaults)
        for interval in RefreshPreferences.supportedIntervals {
            XCTAssertTrue(preferences.setInterval(interval))
            XCTAssertEqual(defaults.double(forKey: "refreshIntervalSeconds"), interval)
            XCTAssertEqual(RefreshPreferences(defaults: defaults).interval, interval)
        }
    }

    /// 非有限及未支持的请求都被拒绝，不覆盖原有合法配置。
    func testRejectsUnsupportedAndNonfiniteWrites() async throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = RefreshPreferences(defaults: defaults)
        XCTAssertTrue(preferences.setInterval(2))
        for value in [0, -1, 0.25, 3, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertFalse(preferences.setInterval(value))
            XCTAssertEqual(preferences.interval, 2)
            XCTAssertEqual(defaults.double(forKey: "refreshIntervalSeconds"), 2)
        }
    }

    /// 持久配置中的错误类型及不支持的数值回退到一秒，不擅自覆盖它们。
    func testInvalidStoredValuesFallBackWithoutRewriting() async throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = RefreshPreferences(defaults: defaults)
        for value in ["2", ["错误类型"], 0, -1, 3] as [Any] {
            defaults.set(value, forKey: "refreshIntervalSeconds")
            XCTAssertEqual(preferences.interval, 1)
            XCTAssertNotNil(defaults.object(forKey: "refreshIntervalSeconds"))
        }
    }

    /// 持久化的非有限数值均不能参与定时器计算。
    func testNonfiniteStoredValuesFallBack() async throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = RefreshPreferences(defaults: defaults)
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            defaults.set(value, forKey: "refreshIntervalSeconds")
            XCTAssertEqual(preferences.interval, 1)
        }
    }

    /// 共享偏好实例能读到同一隔离域中发生的外部更新。
    func testSharedInstanceReadsExternalUpdates() async throws {
        let (defaults, domain) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = RefreshPreferences(defaults: defaults)
        defaults.set(0.5, forKey: "refreshIntervalSeconds")
        XCTAssertEqual(preferences.interval, 0.5)
        defaults.set(2, forKey: "refreshIntervalSeconds")
        XCTAssertEqual(preferences.interval, 2)
    }

    /// 创建测试专用偏好域，清理由测试自身创建的随机名称限定。
    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let domain = "io.github.mac-netspeed.settings-test.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: domain)), domain)
    }
}
