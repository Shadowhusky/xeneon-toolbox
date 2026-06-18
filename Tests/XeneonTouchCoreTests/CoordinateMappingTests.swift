import XCTest
@testable import XeneonTouchCore

final class CoordinateMappingTests: XCTestCase {
    // A typical Edge: 2560x720 panel placed to the right of a 4K display.
    let edge = DisplayRect(x: 3840, y: 0, width: 2560, height: 720)

    let cal = AxisCalibration(minX: 0, maxX: 4095, minY: 0, maxY: 4095)

    func testCenterRawMapsToDisplayCenter() {
        let p = CoordinateMapper.mapToScreen(rawX: 2047.5, rawY: 2047.5, calibration: cal, display: edge)
        XCTAssertEqual(p.x, 3840 + 1280, accuracy: 0.5)
        XCTAssertEqual(p.y, 360, accuracy: 0.5)
    }

    func testOriginRawMapsToDisplayTopLeft() {
        let p = CoordinateMapper.mapToScreen(rawX: 0, rawY: 0, calibration: cal, display: edge)
        XCTAssertEqual(p.x, 3840, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testMaxRawMapsToDisplayBottomRight() {
        let p = CoordinateMapper.mapToScreen(rawX: 4095, rawY: 4095, calibration: cal, display: edge)
        XCTAssertEqual(p.x, 3840 + 2560, accuracy: 0.5)
        XCTAssertEqual(p.y, 720, accuracy: 0.5)
    }

    func testOutOfRangeRawIsClampedToDisplayBounds() {
        let p = CoordinateMapper.mapToScreen(rawX: 9000, rawY: -500, calibration: cal, display: edge)
        XCTAssertEqual(p.x, 3840 + 2560, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testFlipXMirrorsHorizontally() {
        var c = cal; c.flipX = true
        let p = CoordinateMapper.mapToScreen(rawX: 0, rawY: 0, calibration: c, display: edge)
        XCTAssertEqual(p.x, 3840 + 2560, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testFlipYMirrorsVertically() {
        var c = cal; c.flipY = true
        let p = CoordinateMapper.mapToScreen(rawX: 0, rawY: 0, calibration: c, display: edge)
        XCTAssertEqual(p.x, 3840, accuracy: 0.5)
        XCTAssertEqual(p.y, 720, accuracy: 0.5)
    }

    func testSwapXYExchangesAxesBeforeScaling() {
        // raw is near the top of a tall/narrow native orientation; after swap,
        // a small rawY should drive the (wide) screen X near its display origin.
        var c = cal; c.swapXY = true
        let p = CoordinateMapper.mapToScreen(rawX: 4095, rawY: 0, calibration: c, display: edge)
        // nx,ny = (1,0) -> swap -> (0,1) -> screen (origin x, bottom y)
        XCTAssertEqual(p.x, 3840, accuracy: 0.5)
        XCTAssertEqual(p.y, 720, accuracy: 0.5)
    }

    func testDegenerateRangeMapsToDisplayOrigin() {
        let c = AxisCalibration(minX: 100, maxX: 100, minY: 0, maxY: 4095)
        let p = CoordinateMapper.mapToScreen(rawX: 100, rawY: 0, calibration: c, display: edge)
        XCTAssertEqual(p.x, 3840, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }
}
