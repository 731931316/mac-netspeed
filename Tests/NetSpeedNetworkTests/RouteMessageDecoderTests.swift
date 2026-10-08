import Darwin
import Foundation
@testable import NetSpeedNetwork
import XCTest

/// 使用合成路由消息验证解析器，不读取本机网络数据。
final class RouteMessageDecoderTests: XCTestCase {
    /// 空的系统消息列表表示当前没有可用接口记录。
    func testEmptyData() throws {
        XCTAssertEqual(try RouteMessageDecoder.decode(Data()), [])
    }

    /// 原生 if_data64 字段保留 UInt64 边界值。
    func testDecodesNative64BitCounters() throws {
        let records = try RouteMessageDecoder.decode(interfaceMessage(index: 7, received: UInt64.max - 1, sent: 1 << 40))
        XCTAssertEqual(records, [RouteInterfaceRecord(index: 7, flags: Int32(IFF_UP | IFF_RUNNING), receivedBytes: UInt64.max - 1, sentBytes: 1 << 40)])
    }

    /// 仅启用或仅运行的接口均不参与统计，必须同时满足两个状态。
    func testRequiresUpAndRunning() {
        for flags in [Int32(0), Int32(IFF_UP), Int32(IFF_RUNNING)] {
            XCTAssertFalse(RouteInterfaceRecord(index: 2, flags: flags, receivedBytes: 0, sentBytes: 0).isActive)
        }
        XCTAssertTrue(RouteInterfaceRecord(index: 2, flags: Int32(IFF_UP | IFF_RUNNING), receivedBytes: 0, sentBytes: 0).isActive)
    }

    /// 接口消息前后的其他合法消息按长度跳过。
    func testSkipsOtherMessageTypes() throws {
        let other = prefix(length: 4, type: UInt8(RTM_NEWADDR))
        let data = other + interfaceMessage(index: 2) + other + interfaceMessage(index: 3)
        XCTAssertEqual(try RouteMessageDecoder.decode(data).map(\.index), [2, 3])
    }

    /// 合法但未对齐的消息偏移通过 unaligned load 安全解析。
    func testUnalignedInterfaceMessage() throws {
        let other = prefix(length: 5, type: UInt8(RTM_NEWADDR)) + Data([0])
        let data = other + interfaceMessage(index: 2, received: 123, sent: 456)
        let records = try RouteMessageDecoder.decode(data)
        XCTAssertEqual(records.first?.receivedBytes, 123)
        XCTAssertEqual(records.first?.sentBytes, 456)
    }

    /// 共用头部不完整时拒绝读取越界字节。
    func testTruncatedPrefix() {
        expectError(Data([1, 0, UInt8(RTM_VERSION)]), .malformedMessage(offset: 0))
    }

    /// 零长度及短于共用头部的长度不能导致死循环或偏移错误。
    func testTooShortMessageLengths() {
        for length: UInt16 in [0, 1, 2, 3] {
            expectError(prefix(length: length), .malformedMessage(offset: 0))
        }
    }

    /// 宣称长度超出缓冲区时拒绝解析。
    func testDeclaredLengthPastEnd() {
        expectError(prefix(length: 100), .malformedMessage(offset: 0))
    }

    /// 错误版本不能按当前 SDK 的结构强转。
    func testUnsupportedVersion() {
        expectError(prefix(length: 4, version: 0), .unsupportedVersion(version: 0))
    }

    /// IFINFO2 没有完整的 64 位头部时不能读取计数。
    func testTruncatedInterfaceHeader() {
        expectError(prefix(length: 4, type: UInt8(RTM_IFINFO2)), .malformedMessage(offset: 0))
    }

    /// 首条合法消息后的残余字节也必须通过边界校验。
    func testTrailingPartialMessage() {
        let valid = interfaceMessage(index: 2)
        expectError(valid + Data([0]), .malformedMessage(offset: valid.count))
    }

    /// 同一快照不能对同一个接口索引重复计数。
    func testDuplicateInterfaceIndex() {
        expectError(interfaceMessage(index: 2) + interfaceMessage(index: 2), .duplicateInterface(index: 2))
    }

    /// 零不是有效接口索引，拒绝将其传入索引名称解析。
    func testZeroInterfaceIndex() {
        expectError(interfaceMessage(index: 0), .malformedMessage(offset: 0))
    }

    /// 创建使用本机 SDK 布局的合成 IFINFO2 消息。
    private func interfaceMessage(index: UInt16, received: UInt64 = 0, sent: UInt64 = 0) -> Data {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_version = UInt8(RTM_VERSION)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = index
        header.ifm_flags = Int32(IFF_UP | IFF_RUNNING)
        header.ifm_data.ifi_ibytes = received
        header.ifm_data.ifi_obytes = sent
        return withUnsafeBytes(of: &header) { Data($0) }
    }

    /// 创建只包含路由共用头部的合成消息。
    private func prefix(length: UInt16, version: UInt8 = UInt8(RTM_VERSION), type: UInt8 = UInt8(RTM_NEWADDR)) -> Data {
        var length = length
        return withUnsafeBytes(of: &length) { Data($0) } + Data([version, type])
    }

    /// 检查畸形消息产生约定错误而非崩溃或部分成功。
    private func expectError(_ data: Data, _ expected: NetworkReadError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try RouteMessageDecoder.decode(data), file: file, line: line) { error in
            XCTAssertEqual(error as? NetworkReadError, expected, file: file, line: line)
        }
    }
}
