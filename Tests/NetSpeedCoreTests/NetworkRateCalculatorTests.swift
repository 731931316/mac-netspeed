import NetSpeedCore
import XCTest

/// 验证接口独立差值、计数边界及采样时间异常。
final class NetworkRateCalculatorTests: XCTestCase {
    /// 首次快照只建立基线，不将开机以来的计数当作当前速率。
    func testFirstSnapshotEstablishesBaseline() {
        var calculator = NetworkRateCalculator()
        let rate = calculator.consume(snapshot(10, [counter("en0", 50_000, 25_000)]))
        XCTAssertEqual(rate, TransferRate(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, interfaceNames: ["en0"]))
    }

    /// 按真实采样间隔计算，定时器延迟不会被当作一秒。
    func testUsesActualElapsedTime() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(10, [counter("en0", 100, 200)]))
        let rate = calculator.consume(snapshot(12.5, [counter("en0", 350, 700)]))
        XCTAssertEqual(rate.downloadBytesPerSecond, 100)
        XCTAssertEqual(rate.uploadBytesPerSecond, 200)
    }

    /// 超过 32 位及浮点整数精度边界时仍保留小字节差值。
    func testNative64BitCountersPreserveSmallDeltas() {
        var calculator = NetworkRateCalculator()
        let base = UInt64.max - 100
        _ = calculator.consume(snapshot(1, [counter("en0", base, base)]))
        let rate = calculator.consume(snapshot(2, [counter("en0", base + 3, base + 7)]))
        XCTAssertEqual(rate.downloadBytesPerSecond, 3)
        XCTAssertEqual(rate.uploadBytesPerSecond, 7)
    }

    /// 网卡切换后新接口先建立基线，不累加该接口的历史计数。
    func testInterfaceSwitchDoesNotCreateSpike() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 10_000, 20_000)]))
        let switched = calculator.consume(snapshot(2, [counter("en7", 9_000_000, 8_000_000)]))
        XCTAssertEqual(switched.downloadBytesPerSecond, 0)
        XCTAssertEqual(switched.uploadBytesPerSecond, 0)
        XCTAssertEqual(switched.interfaceNames, ["en7"])
        let next = calculator.consume(snapshot(3, [counter("en7", 9_000_100, 8_000_200)]))
        XCTAssertEqual(next.downloadBytesPerSecond, 100)
        XCTAssertEqual(next.uploadBytesPerSecond, 200)
    }

    /// 新增接口不影响已有接口差值，下一次采样再参与合计。
    func testAddedInterfaceDoesNotHideExistingTraffic() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 100, 200)]))
        let added = calculator.consume(snapshot(2, [counter("en7", 90_000, 80_000), counter("en0", 110, 220)]))
        XCTAssertEqual(added.downloadBytesPerSecond, 10)
        XCTAssertEqual(added.uploadBytesPerSecond, 20)
        XCTAssertEqual(added.interfaceNames, ["en0", "en7"])
        let next = calculator.consume(snapshot(3, [counter("en7", 90_100, 80_200), counter("en0", 120, 240)]))
        XCTAssertEqual(next.downloadBytesPerSecond, 110)
        XCTAssertEqual(next.uploadBytesPerSecond, 220)
    }

    /// 消失接口及随后重现接口不会沿用断开前的基线。
    func testDisappearedInterfaceLosesBaseline() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 100, 200)]))
        let empty = calculator.consume(snapshot(2, []))
        XCTAssertEqual(empty.interfaceNames, [])
        let returned = calculator.consume(snapshot(3, [counter("en0", 900_000, 800_000)]))
        XCTAssertEqual(returned.downloadBytesPerSecond, 0)
        XCTAssertEqual(returned.uploadBytesPerSecond, 0)
    }

    /// 接收计数回退时整条接口重新建立基线。
    func testReceivedCounterResetRebaselinesInterface() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 1_000, 2_000)]))
        let reset = calculator.consume(snapshot(2, [counter("en0", 5, 2_500)]))
        XCTAssertEqual(reset.downloadBytesPerSecond, 0)
        XCTAssertEqual(reset.uploadBytesPerSecond, 0)
        let next = calculator.consume(snapshot(3, [counter("en0", 15, 2_520)]))
        XCTAssertEqual(next.downloadBytesPerSecond, 10)
        XCTAssertEqual(next.uploadBytesPerSecond, 20)
    }

    /// 发送计数回退不会因无符号下溢产生巨大的上传速率。
    func testSentCounterResetDoesNotUnderflow() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 100, UInt64.max)]))
        let rate = calculator.consume(snapshot(2, [counter("en0", 200, 5)]))
        XCTAssertEqual(rate.downloadBytesPerSecond, 0)
        XCTAssertEqual(rate.uploadBytesPerSecond, 0)
    }

    /// 重复时间返回零并刷新基线，后续正常时间可恢复计算。
    func testZeroElapsedTimeRebaselines() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(10, [counter("en0", 100, 200)]))
        let invalid = calculator.consume(snapshot(10, [counter("en0", 150, 250)]))
        XCTAssertEqual(invalid.downloadBytesPerSecond, 0)
        let next = calculator.consume(snapshot(11, [counter("en0", 160, 270)]))
        XCTAssertEqual(next.downloadBytesPerSecond, 10)
        XCTAssertEqual(next.uploadBytesPerSecond, 20)
    }

    /// 倒退的单调时间不参与差值，也不阻止下一次正常采样。
    func testNegativeElapsedTimeRebaselines() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(10, [counter("en0", 100, 200)]))
        let invalid = calculator.consume(snapshot(9, [counter("en0", 150, 250)]))
        XCTAssertEqual(invalid.downloadBytesPerSecond, 0)
        let next = calculator.consume(snapshot(10, [counter("en0", 160, 270)]))
        XCTAssertEqual(next.downloadBytesPerSecond, 10)
    }

    /// 非有限及负时间清空基线，下一次有效快照先重新开始。
    func testInvalidTimestampClearsBaseline() {
        for invalidTime in [Double.nan, Double.infinity, -Double.infinity, -1] {
            var calculator = NetworkRateCalculator()
            _ = calculator.consume(snapshot(1, [counter("en0", 100, 200)]))
            let invalid = calculator.consume(snapshot(invalidTime, [counter("en0", 900, 900)]))
            XCTAssertEqual(invalid.downloadBytesPerSecond, 0)
            XCTAssertEqual(invalid.uploadBytesPerSecond, 0)
            let next = calculator.consume(snapshot(2, [counter("en0", 1_000, 1_000)]))
            XCTAssertEqual(next.downloadBytesPerSecond, 0)
        }
    }

    /// 明确 reset 后不沿用睡眠前或读取失败前的计数。
    func testResetDiscardsAllBaselines() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 100, 200)]))
        calculator.reset()
        let rate = calculator.consume(snapshot(100, [counter("en0", 900_000, 800_000)]))
        XCTAssertEqual(rate.downloadBytesPerSecond, 0)
        XCTAssertEqual(rate.uploadBytesPerSecond, 0)
    }

    /// 极小但正的时间间隔造成浮点溢出时仍返回有限的安全值。
    func testRateOverflowReturnsZero() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(0, [counter("en0", 0, 0)]))
        let rate = calculator.consume(snapshot(Double.leastNonzeroMagnitude, [counter("en0", 10, 20)]))
        XCTAssertEqual(rate.downloadBytesPerSecond, 0)
        XCTAssertEqual(rate.uploadBytesPerSecond, 0)
    }

    /// 重复接口标识不被合计两次，也不会触发字典初始化异常。
    func testDuplicateInterfaceIsNotDoubleCounted() {
        var calculator = NetworkRateCalculator()
        _ = calculator.consume(snapshot(1, [counter("en0", 0, 0)]))
        let rate = calculator.consume(snapshot(2, [counter("en0", 100, 200), counter("en0", 100, 200)]))
        XCTAssertEqual(rate.downloadBytesPerSecond, 100)
        XCTAssertEqual(rate.uploadBytesPerSecond, 200)
        XCTAssertEqual(rate.interfaceNames, ["en0"])
    }

    /// 创建带单调时间的测试快照。
    private func snapshot(_ timestamp: Double, _ interfaces: [InterfaceCounters]) -> NetworkSnapshot {
        NetworkSnapshot(timestamp: timestamp, interfaces: interfaces)
    }

    /// 创建单个接口的测试计数。
    private func counter(_ name: String, _ received: UInt64, _ sent: UInt64) -> InterfaceCounters {
        InterfaceCounters(identifier: name, receivedBytes: received, sentBytes: sent)
    }
}
