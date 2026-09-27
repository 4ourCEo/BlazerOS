import BlazerCore
import XCTest

final class PhoneTargetTests: XCTestCase {
    func testIPhone16Canvas() {
        XCTAssertEqual(PhoneTarget.model, "iPhone 16")
        XCTAssertEqual(PhoneTarget.systemVersion, "26.0")
        XCTAssertEqual(PhoneTarget.width, 393)
        XCTAssertEqual(PhoneTarget.height, 852)
        XCTAssertEqual(PhoneTarget.scale, 3)
        XCTAssertEqual(PhoneTarget.pixelWidth, 1179)
        XCTAssertEqual(PhoneTarget.pixelHeight, 2556)
        XCTAssertEqual(PhoneTarget.width * PhoneTarget.scale, PhoneTarget.pixelWidth)
        XCTAssertEqual(PhoneTarget.height * PhoneTarget.scale, PhoneTarget.pixelHeight)
        XCTAssertEqual(PhoneTarget.topInset, 59)
        XCTAssertEqual(PhoneTarget.bottomInset, 34)
        XCTAssertTrue(PhoneTarget.hasDynamicIsland)
        XCTAssertFalse(PhoneTarget.hasAlwaysOnDisplay)
        XCTAssertFalse(PhoneTarget.hasProMotion)
        XCTAssertNotEqual(PhoneTarget.width, 390)
        XCTAssertNotEqual(PhoneTarget.width, 402)
        XCTAssertNotEqual(PhoneTarget.width, 430)
        XCTAssertEqual(PhoneTarget.bundleIdentifier, "com.blazer.os")
        XCTAssertEqual(PhoneTarget.appGroup, "group.com.blazer.os")
    }
}
