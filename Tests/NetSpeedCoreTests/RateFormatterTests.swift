import NetSpeedCore
import XCTest

/// 验证十进制单位边界、显示精度与异常值格式化。
final class RateFormatterTests: XCTestCase {
    /// 零及不可展示的值统一使用安全的零速率文案。
    func testZeroAndInvalidValues() {
        for value in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(RateFormatter.string(bytesPerSecond: value), "0 B/s")
        }
    }

    /// 小于千字节的非零速度使用字节单位与一位小数。
    func testByteValues() {
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1), "1.0 B/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 123.44), "123.4 B/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 999.94), "999.9 B/s")
    }

    /// 单位边界按 1000 而非 1024 提升。
    func testDecimalUnitBoundaries() {
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1_000), "1.0 KB/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1_000_000), "1.0 MB/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1_000_000_000), "1.0 GB/s")
    }

    /// 临近边界的舍入结果提升到下一个单位，保持简洁展示。
    func testRoundingAcrossUnitBoundary() {
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 999.99), "1.0 KB/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 999_999.99), "1.0 MB/s")
    }

    /// 常见速度在各单位中都保持一位小数。
    func testFractionalLargerUnits() {
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1_234), "1.2 KB/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 12_340_000), "12.3 MB/s")
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1_230_000_000), "1.2 GB/s")
    }

    /// 超过最大展示单位后继续使用 GB/s，不生成未约定的单位。
    func testValuesAboveGigabyteRemainGigabytes() {
        XCTAssertEqual(RateFormatter.string(bytesPerSecond: 1_000_000_000_000), "1000.0 GB/s")
    }
}
