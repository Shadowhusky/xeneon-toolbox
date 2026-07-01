import XCTest
@testable import XeneonTouchCore

final class DigitizerReportTests: XCTestCase {
    /// Builds a report payload (no report-id prefix) with the given fingers, each
    /// in its own slot: status byte (tip + id), little-endian X, little-endian Y.
    private func payload(_ fingers: [(slot: Int, id: Int, x: Int, y: Int)]) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 53)   // 10*5 + scanTime(2) + count(1)
        for f in fingers {
            let off = f.slot * 5
            p[off] = UInt8(0x01 | ((f.id & 0x0F) << 4))
            p[off + 1] = UInt8(f.x & 0xFF); p[off + 2] = UInt8((f.x >> 8) & 0xFF)
            p[off + 3] = UInt8(f.y & 0xFF); p[off + 4] = UInt8((f.y >> 8) & 0xFF)
        }
        p[52] = UInt8(fingers.count)
        return p
    }

    func testNoFingersDown() {
        XCTAssertEqual(DigitizerReport.parse(payload: [UInt8](repeating: 0, count: 53)), [])
    }

    func testSingleFinger() {
        let p = payload([(slot: 0, id: 0, x: 1234, y: 567)])
        XCTAssertEqual(DigitizerReport.parse(payload: p), [RawContact(id: 0, x: 1234, y: 567)])
    }

    func testTwoFingersWithIds() {
        let p = payload([(slot: 0, id: 2, x: 100, y: 200), (slot: 1, id: 7, x: 9000, y: 8000)])
        XCTAssertEqual(DigitizerReport.parse(payload: p),
                       [RawContact(id: 2, x: 100, y: 200), RawContact(id: 7, x: 9000, y: 8000)])
    }

    func testFingerInLaterSlotOnly() {
        // A finger reported in slot 4 while earlier slots have tip=0 must still parse.
        let p = payload([(slot: 4, id: 5, x: 16383, y: 9599)])
        XCTAssertEqual(DigitizerReport.parse(payload: p), [RawContact(id: 5, x: 16383, y: 9599)])
    }

    func testTruncatedPayloadStopsCleanly() {
        // Short buffer: parse only whole finger records present, no crash.
        let p = payload([(slot: 0, id: 0, x: 50, y: 60)])
        XCTAssertEqual(DigitizerReport.parse(payload: Array(p.prefix(5))), [RawContact(id: 0, x: 50, y: 60)])
        XCTAssertEqual(DigitizerReport.parse(payload: Array(p.prefix(3))), [])
    }
}

final class OneEuroFilterTests: XCTestCase {
    func testFirstSampleIsPassthrough() {
        var f = OneEuroFilter()
        XCTAssertEqual(f.filter(42, dt: 1.0 / 120), 42, accuracy: 0.0001)
    }

    func testStepIsDampedNotOvershot() {
        var f = OneEuroFilter()
        _ = f.filter(0, dt: 1.0 / 120)
        let out = f.filter(100, dt: 1.0 / 120)
        XCTAssertGreaterThan(out, 0)      // moves toward the new value
        XCTAssertLessThan(out, 100)       // but lags — that's the smoothing
    }

    func testConvergesToConstant() {
        var f = OneEuroFilter()
        var out = 0.0
        for _ in 0..<200 { out = f.filter(100, dt: 1.0 / 120) }
        XCTAssertEqual(out, 100, accuracy: 0.5)
    }

    func testResetClearsHistory() {
        var f = OneEuroFilter()
        _ = f.filter(50, dt: 1.0 / 120)
        f.reset()
        XCTAssertEqual(f.filter(7, dt: 1.0 / 120), 7, accuracy: 0.0001)   // passthrough again
    }
}

final class MultiTouchRecognizerTests: XCTestCase {
    private func c(_ id: Int, _ x: Double, _ y: Double) -> TouchContact {
        TouchContact(id: id, point: ScreenPoint(x: x, y: y))
    }

    // MARK: single finger (delegated to TouchStateMachine)

    func testSingleFingerTap() {
        var r = MultiTouchRecognizer()
        XCTAssertEqual(r.update(contacts: [c(0, 100, 100)]), [.move(ScreenPoint(x: 100, y: 100))])
        XCTAssertEqual(r.update(contacts: []), [.press(ScreenPoint(x: 100, y: 100)),
                                                .release(ScreenPoint(x: 100, y: 100))])
    }

    func testSingleFingerScroll() {
        var r = MultiTouchRecognizer()
        _ = r.update(contacts: [c(0, 100, 100)])
        XCTAssertEqual(r.update(contacts: [c(0, 105, 140)]),
                       [.scroll(dx: 0, dy: 0, phase: .began), .scroll(dx: 5, dy: 40, phase: .changed)])
        XCTAssertEqual(r.update(contacts: []), [.scroll(dx: 0, dy: 0, phase: .ended)])
    }

    // MARK: two-finger pan

    func testTwoFingerPan() {
        var r = MultiTouchRecognizer()
        XCTAssertEqual(r.update(contacts: [c(0, 100, 100), c(1, 200, 100)]), [])   // begin, undecided
        // both fingers move down 30px → centroid translates, spread unchanged → pan
        XCTAssertEqual(r.update(contacts: [c(0, 100, 130), c(1, 200, 130)]),
                       [.scroll(dx: 0, dy: 0, phase: .began), .scroll(dx: 0, dy: 30, phase: .changed)])
        XCTAssertEqual(r.update(contacts: [c(0, 100, 150), c(1, 200, 150)]),
                       [.scroll(dx: 0, dy: 20, phase: .changed)])
        XCTAssertEqual(r.update(contacts: []), [.scroll(dx: 0, dy: 0, phase: .ended)])
    }

    // MARK: two-finger pinch

    func testTwoFingerPinchZooms() {
        var r = MultiTouchRecognizer()
        _ = r.update(contacts: [c(0, 100, 100), c(1, 200, 100)])   // spread 100
        // spread to 140 (centroid fixed at 150,100) → zoom, anchored on the midpoint
        XCTAssertEqual(r.update(contacts: [c(0, 80, 100), c(1, 220, 100)]),
                       [.zoom(delta: 40, center: ScreenPoint(x: 150, y: 100))])
        XCTAssertEqual(r.update(contacts: [c(0, 60, 100), c(1, 240, 100)]),
                       [.zoom(delta: 40, center: ScreenPoint(x: 150, y: 100))])
        XCTAssertEqual(r.update(contacts: []), [])   // pinch end emits nothing
    }

    // MARK: transitions

    func testSecondFingerCancelsPendingTapNoClick() {
        var r = MultiTouchRecognizer()
        _ = r.update(contacts: [c(0, 100, 100)])                       // single pending
        XCTAssertEqual(r.update(contacts: [c(0, 100, 100), c(1, 200, 100)]), [])  // cancel, no click
        // lifting both ends cleanly without a click
        XCTAssertEqual(r.update(contacts: []), [])
    }

    func testSecondFingerDuringDragReleasesHeldButton() {
        var r = MultiTouchRecognizer()
        _ = r.update(contacts: [c(0, 100, 100)])
        _ = r.update(contacts: [c(0, 140, 105)])    // horizontal → dragging (press+drag)
        // a second finger lands → release the held button, then go multi
        XCTAssertEqual(r.update(contacts: [c(0, 140, 105), c(1, 240, 105)]),
                       [.release(ScreenPoint(x: 140, y: 105))])
    }

    func testDrainWaitsForFullRelease() {
        var r = MultiTouchRecognizer()
        _ = r.update(contacts: [c(0, 100, 100), c(1, 200, 100)])
        _ = r.update(contacts: [c(0, 100, 130), c(1, 200, 130)])   // pan
        XCTAssertEqual(r.update(contacts: [c(0, 100, 140)]), [.scroll(dx: 0, dy: 0, phase: .ended)])
        // one finger still down — must NOT start a new single gesture
        XCTAssertEqual(r.update(contacts: [c(0, 100, 160)]), [])
        XCTAssertEqual(r.update(contacts: []), [])
        // fresh gesture works again afterwards
        XCTAssertEqual(r.update(contacts: [c(0, 50, 50)]), [.move(ScreenPoint(x: 50, y: 50))])
    }

    func testResetWhilePanningEndsScroll() {
        var r = MultiTouchRecognizer()
        _ = r.update(contacts: [c(0, 100, 100), c(1, 200, 100)])
        _ = r.update(contacts: [c(0, 100, 130), c(1, 200, 130)])
        XCTAssertEqual(r.reset(), [.scroll(dx: 0, dy: 0, phase: .ended)])
    }
}
