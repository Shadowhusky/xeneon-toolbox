import XCTest
@testable import ToolboxKit

final class FocusTimerStateTests: XCTestCase {
    func testStartsStoppedAtFullDuration() {
        let s = FocusTimerState(minutes: 25)
        XCTAssertEqual(s.total, 25 * 60)
        XCTAssertEqual(s.remaining, 25 * 60)
        XCTAssertFalse(s.running)
        XCTAssertEqual(s.clock, "25:00")
        XCTAssertEqual(s.fraction, 0)
    }

    func testTickOnlyCountsWhileRunning() {
        var s = FocusTimerState(minutes: 1)
        XCTAssertFalse(s.tick())            // not running → no change
        XCTAssertEqual(s.remaining, 60)
        s.toggle()                          // start
        XCTAssertFalse(s.tick())
        XCTAssertEqual(s.remaining, 59)
    }

    func testTickReturnsTrueExactlyOnCompletion() {
        var s = FocusTimerState(minutes: 1)
        s.toggle()
        for _ in 0..<59 { XCTAssertFalse(s.tick()) }
        XCTAssertEqual(s.remaining, 1)
        XCTAssertTrue(s.tick())             // hits zero this tick
        XCTAssertEqual(s.remaining, 0)
        XCTAssertFalse(s.running)           // auto-stops
        XCTAssertFalse(s.tick())            // no underflow, no repeat completion
        XCTAssertEqual(s.remaining, 0)
    }

    func testSetDurationResetsAndStops() {
        var s = FocusTimerState(minutes: 25)
        s.toggle(); _ = s.tick()
        s.setDuration(minutes: 5)
        XCTAssertEqual(s.total, 5 * 60)
        XCTAssertEqual(s.remaining, 5 * 60)
        XCTAssertFalse(s.running)
    }

    func testToggleFromFinishedRestartsFromFull() {
        var s = FocusTimerState(minutes: 1)
        s.toggle()
        for _ in 0..<60 { _ = s.tick() }
        XCTAssertEqual(s.remaining, 0)
        s.toggle()                          // start again from a finished state
        XCTAssertTrue(s.running)
        XCTAssertEqual(s.remaining, 60)
    }

    func testResetStopsAndRestoresRemaining() {
        var s = FocusTimerState(minutes: 10)
        s.toggle(); for _ in 0..<120 { _ = s.tick() }
        XCTAssertEqual(s.remaining, 10 * 60 - 120)
        s.reset()
        XCTAssertFalse(s.running)
        XCTAssertEqual(s.remaining, 10 * 60)
    }

    func testFractionProgresses() {
        var s = FocusTimerState(minutes: 1)
        s.toggle()
        for _ in 0..<30 { _ = s.tick() }
        XCTAssertEqual(s.fraction, 0.5, accuracy: 0.001)
    }

    func testClockFormatsMinutesSeconds() {
        var s = FocusTimerState(minutes: 45)
        XCTAssertEqual(s.clock, "45:00")
        s.toggle(); _ = s.tick()
        XCTAssertEqual(s.clock, "44:59")
    }
}
