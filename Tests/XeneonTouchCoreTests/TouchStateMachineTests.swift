import XCTest
@testable import XeneonTouchCore

final class TouchStateMachineTests: XCTestCase {
    let a = ScreenPoint(x: 100, y: 100)
    let vUp = ScreenPoint(x: 105, y: 130)     // mostly-vertical move (dy 30, dx 5)
    let hMove = ScreenPoint(x: 140, y: 105)   // mostly-horizontal move (dx 40, dy 5)
    let jitter = ScreenPoint(x: 104, y: 103)  // within tap slop (10)

    // MARK: tap

    func testContactBeginOnlyMovesCursorNoPressYet() {
        var sm = TouchStateMachine()
        XCTAssertEqual(sm.update(contact: true, point: a), [.move(a)])
    }

    func testTapClicksOnRelease() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: false, point: nil), [.press(a), .release(a)])
    }

    func testJitterWithinSlopStillTaps() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: true, point: jitter), [.move(jitter)])
        XCTAssertEqual(sm.update(contact: false, point: nil), [.press(jitter), .release(jitter)])
    }

    func testNoMovementEmitsNothing() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: true, point: a), [])
    }

    // MARK: scroll

    func testVerticalMoveScrollsAndDoesNotClick() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: true, point: vUp),
                       [.scroll(dx: 0, dy: 0, phase: .began),
                        .scroll(dx: 5, dy: 30, phase: .changed)])
        // releasing a scroll closes the gesture and must NOT emit a click
        XCTAssertEqual(sm.update(contact: false, point: nil), [.scroll(dx: 0, dy: 0, phase: .ended)])
    }

    func testScrollContinuesWithDeltaSinceLast() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: true, point: vUp)
        let next = ScreenPoint(x: 106, y: 150)
        XCTAssertEqual(sm.update(contact: true, point: next), [.scroll(dx: 1, dy: 20, phase: .changed)])
    }

    // MARK: drag (sliders / horizontal controls)

    func testHorizontalMovePressesThenDrags() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: true, point: hMove), [.press(a), .drag(hMove)])
    }

    func testDragReleasesOnContactEnd() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: true, point: hMove)
        XCTAssertEqual(sm.update(contact: false, point: nil), [.release(hMove)])
    }

    // MARK: reset

    func testResetWhileDraggingReleasesHeldButton() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: true, point: hMove)
        XCTAssertEqual(sm.reset(), [.release(hMove)])
    }

    func testResetWhileScrollingClosesTheGesture() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: true, point: vUp)
        XCTAssertEqual(sm.reset(), [.scroll(dx: 0, dy: 0, phase: .ended)])
    }

    func testResetWhilePendingEmitsNothing() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.reset(), [])   // never pressed, nothing to release
    }

    func testResetWhileIdleEmitsNothing() {
        var sm = TouchStateMachine()
        XCTAssertEqual(sm.reset(), [])
    }

    // MARK: sequences

    func testTapThenSecondGestureStartsFresh() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: false, point: nil)
        XCTAssertEqual(sm.update(contact: true, point: vUp), [.move(vUp)])
    }

    func testReleaseWithoutContactEmitsNothing() {
        var sm = TouchStateMachine()
        XCTAssertEqual(sm.update(contact: false, point: nil), [])
    }
}
