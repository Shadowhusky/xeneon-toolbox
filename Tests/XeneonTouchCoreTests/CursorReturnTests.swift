import XCTest
@testable import XeneonTouchCore

final class CursorReturnTests: XCTestCase {
    private let home = ScreenPoint(x: 400, y: 300)     // on the main display
    private let corner = ScreenPoint(x: 2746, y: 1799) // the Edge's park pixel

    func testTapReturnsToWhereThePointerWas() {
        var r = CursorReturn()
        r.touchBegan(pointerAt: home)
        r.posted()
        XCTAssertEqual(r.destination(), home)
    }

    func testGestureThatPostedNothingLeavesThePointerAlone() {
        var r = CursorReturn()
        r.touchBegan(pointerAt: home)
        XCTAssertNil(r.destination())
        XCTAssertNil(r.home)
    }

    func testRealMouseMotionMidGestureCancelsTheReturn() {
        var r = CursorReturn()
        r.touchBegan(pointerAt: home)
        r.posted()
        r.realPointerMoved()
        XCTAssertNil(r.destination())
    }

    func testHomeSurvivesATouchThatInterruptsMomentum() {
        var r = CursorReturn()
        r.touchBegan(pointerAt: home)
        r.posted()
        // Momentum still coasting (no destination yet); the pointer sits at the corner.
        r.touchBegan(pointerAt: corner)
        r.posted()
        XCTAssertEqual(r.destination(), home)
    }

    func testStateResetsBetweenGestures() {
        var r = CursorReturn()
        r.touchBegan(pointerAt: home)
        r.posted()
        _ = r.destination()
        r.posted()   // the return move itself must not count as a gesture
        let elsewhere = ScreenPoint(x: 10, y: 10)
        r.touchBegan(pointerAt: elsewhere)
        r.posted()
        XCTAssertEqual(r.destination(), elsewhere)
    }

    func testUnknownPointerPositionYieldsNoReturn() {
        var r = CursorReturn()
        r.touchBegan(pointerAt: nil)
        r.posted()
        XCTAssertNil(r.destination())
    }
}
