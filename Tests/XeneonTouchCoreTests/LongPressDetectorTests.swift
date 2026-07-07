import XCTest
@testable import XeneonTouchCore

final class LongPressDetectorTests: XCTestCase {
    let p = ScreenPoint(x: 100, y: 100)
    let near = ScreenPoint(x: 108, y: 104)   // within slop (16)
    let far = ScreenPoint(x: 140, y: 100)    // past slop

    // MARK: engage

    func testHoldStillFiresAfterDuration() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: p, now: 0.0), .none)   // arm
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: p, now: 0.3), .none)   // still waiting
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: near, now: 0.6), .fire(p)) // engaged (slop ok)
    }

    func testDoesNotFireWhenDisabled() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        XCTAssertEqual(lp.update(enabled: false, count: 1, point: p, now: 0.0), .none)
        XCTAssertEqual(lp.update(enabled: false, count: 1, point: p, now: 1.0), .none)
    }

    func testMovingPastSlopCancels() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: p, now: 0.0), .none)
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: far, now: 0.2), .none)  // moved → not a press
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: far, now: 0.9), .none)  // never re-arms this contact
    }

    // MARK: the regression — release after mid-gesture disable

    /// The picker disables long-press detection the instant it appears (so no new
    /// press can start under the open menu), but the finger is still down. An
    /// engaged press must keep owning its contact until the finger lifts, and the
    /// lift itself must be swallowed — otherwise the release is handed back to the
    /// pointer pipeline and lands as a tap that dismisses the just-opened menu.
    func testEngagedPressSwallowsReleaseEvenAfterDisabledMidGesture() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        _ = lp.update(enabled: true, count: 1, point: p, now: 0.0)
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: p, now: 0.6), .fire(p))
        // App disables detection while the finger is still down.
        XCTAssertEqual(lp.update(enabled: false, count: 1, point: p, now: 0.65), .swallow)
        XCTAssertEqual(lp.update(enabled: false, count: 1, point: p, now: 0.70), .swallow)
        // Finger lifts — the release frame must be swallowed, not passed through.
        XCTAssertEqual(lp.update(enabled: false, count: 0, point: nil, now: 0.75), .swallow)
        // Fully idle afterwards.
        XCTAssertEqual(lp.update(enabled: false, count: 0, point: nil, now: 0.80), .none)
    } 

    func testReleaseBeforeEngageIsNotSwallowed() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        _ = lp.update(enabled: true, count: 1, point: p, now: 0.0)
        // Finger lifts before the duration — a normal tap; the pointer pipeline
        // must handle it, so the detector passes the frame through.
        XCTAssertEqual(lp.update(enabled: true, count: 0, point: nil, now: 0.2), .none)
    }

    func testSecondFingerEndsPress() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        _ = lp.update(enabled: true, count: 1, point: p, now: 0.0)
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: p, now: 0.6), .fire(p))
        // A second finger arriving ends the engaged press (swallowed), then idle.
        XCTAssertEqual(lp.update(enabled: true, count: 2, point: p, now: 0.7), .swallow)
        XCTAssertEqual(lp.update(enabled: true, count: 0, point: nil, now: 0.8), .none)
    }

    func testResetClearsEngagedState() {
        var lp = LongPressDetector(duration: 0.5, slop: 16)
        _ = lp.update(enabled: true, count: 1, point: p, now: 0.0)
        _ = lp.update(enabled: true, count: 1, point: p, now: 0.6)   // engaged
        lp.reset()
        // After reset a fresh hold arms from scratch.
        XCTAssertEqual(lp.update(enabled: true, count: 1, point: p, now: 1.0), .none)
    }
}
