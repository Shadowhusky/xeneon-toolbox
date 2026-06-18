import XCTest
@testable import XeneonTouchCore

final class TouchStateMachineTests: XCTestCase {
    let a = ScreenPoint(x: 100, y: 100)
    let b = ScreenPoint(x: 150, y: 120)

    func testContactBeginPressesAtPoint() {
        var sm = TouchStateMachine()
        XCTAssertEqual(sm.update(contact: true, point: a), [.moveAndPress(a)])
    }

    func testMovementWhileDownDrags() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: true, point: b), [.drag(b)])
    }

    func testNoMovementWhileDownEmitsNothing() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.update(contact: true, point: a), [])
    }

    func testContactEndReleasesAtLastPoint() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: true, point: b)
        XCTAssertEqual(sm.update(contact: false, point: nil), [.release(b)])
    }

    func testReleaseWithoutPriorContactEmitsNothing() {
        var sm = TouchStateMachine()
        XCTAssertEqual(sm.update(contact: false, point: nil), [])
    }

    func testTapThenSecondTapPressesAgain() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.update(contact: false, point: nil)
        XCTAssertEqual(sm.update(contact: true, point: b), [.moveAndPress(b)])
    }

    func testResetWhileDownReleasesHeldButton() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        XCTAssertEqual(sm.reset(), [.release(a)])
    }

    func testResetWhileUpEmitsNothing() {
        var sm = TouchStateMachine()
        XCTAssertEqual(sm.reset(), [])
    }

    func testResetIsIdempotent() {
        var sm = TouchStateMachine()
        _ = sm.update(contact: true, point: a)
        _ = sm.reset()
        XCTAssertEqual(sm.reset(), [])
    }
}
