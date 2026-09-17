import XCTest
@testable import XeneonTouchCore

final class TouchRecoveryPolicyTests: XCTestCase {
    func testTouchOffNeverReacquires() {
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: false, deviceDetected: false, displayPresent: true, seized: false, seizeRetries: 0, ticksSinceRetry: 0))
    }

    /// THE regression (2026-07-11 log: "digitizer lost" then silence): the device
    /// vanished but the manager-level seize flag stays stale-true. Device presence
    /// must be checked FIRST — a lost device always warrants reacquiring, whatever
    /// the seize flag claims.
    func testLostDeviceReacquiresEvenWithStaleSeizedFlag() {
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: true, seized: true, seizeRetries: 0, ticksSinceRetry: 0))
    }

    func testLostDeviceReacquiresRegardlessOfRetryCount() {
        // Searching for the device retries forever (the panel may be replugged any
        // time); the retry budget applies only to the seize-upgrade path.
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: true, seized: false, seizeRetries: 99, ticksSinceRetry: 0))
    }

    /// The Edge powers its touch controller down with the display: while the panel
    /// is asleep/unplugged the digitizer is genuinely unpowered, so churning the
    /// HID manager is futile — wait for the display to return (a display-change
    /// notification reacquires immediately).
    func testPanelAsleepDoesNotChurn() {
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: false, seized: true, seizeRetries: 0, ticksSinceRetry: 0))
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: false, seized: false, seizeRetries: 0, ticksSinceRetry: 0))
    }

    func testHealthyDetectedAndSeizedDoesNothing() {
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: true, seizeRetries: 3, ticksSinceRetry: 50))
    }

    func testPresentButNotSeizedRetriesFastThenSlowForever() {
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 0, ticksSinceRetry: 0))
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 4, ticksSinceRetry: 0))
        // Past the fast budget: back off to every 10th watchdog tick, but never stop.
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 5, ticksSinceRetry: 3))
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 5, ticksSinceRetry: 10))
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 50, ticksSinceRetry: 10))
    }
}
