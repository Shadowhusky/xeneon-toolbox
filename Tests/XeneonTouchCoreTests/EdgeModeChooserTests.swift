import XCTest
@testable import XeneonTouchCore

final class EdgeModeChooserTests: XCTestCase {
    func testPrefersSafeNativeMode() {
        let modes = [DisplayModeCandidate(number: 28, width: 2560, height: 720, density: 1, flags: 0x1),
                     DisplayModeCandidate(number: 40, width: 2560, height: 720, density: 1, flags: 0x3),
                     DisplayModeCandidate(number: 26, width: 1920, height: 1080, density: 1, flags: 0x2000007)]
        XCTAssertEqual(EdgeModeChooser.best(from: modes)?.number, 40)
    }

    func testIgnoresHiDPIDuplicate() {
        let modes = [DisplayModeCandidate(number: 9, width: 1280, height: 360, density: 2, flags: 0x1),
                     DisplayModeCandidate(number: 28, width: 2560, height: 720, density: 1, flags: 0x1)]
        XCTAssertEqual(EdgeModeChooser.best(from: modes)?.number, 28)
    }

    func testNilWhenNoNativeMode() {
        XCTAssertNil(EdgeModeChooser.best(from: [DisplayModeCandidate(number: 26, width: 1920, height: 1080, density: 1, flags: 0x7)]))
    }

    func testIsNative() {
        XCTAssertTrue(EdgeModeChooser.isNative(width: 2560, height: 720, pixelWidth: 2560))
        XCTAssertFalse(EdgeModeChooser.isNative(width: 1280, height: 360, pixelWidth: 2560))
        XCTAssertFalse(EdgeModeChooser.isNative(width: 1920, height: 1080, pixelWidth: 1920))
    }
}
