import XCTest
@testable import XeneonTouchCore

final class TouchRecoveryPolicyTests: XCTestCase {
    func testTouchOffNeverReacquires() {
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: false, deviceDetected: false, displayPresent: true, seized: false, seizeRetries: 0))
    }

    /// THE regression (2026-07-11 log: "digitizer lost" then silence): the device
    /// vanished but the manager-level seize flag stays stale-true. Device presence
    /// must be checked FIRST — a lost device always warrants reacquiring, whatever
    /// the seize flag claims.
    func testLostDeviceReacquiresEvenWithStaleSeizedFlag() {
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: true, seized: true, seizeRetries: 0))
    }

    func testLostDeviceReacquiresRegardlessOfRetryCount() {
        // Searching for the device retries forever (the panel may be replugged any
        // time); the retry cap applies only to the seize-upgrade path.
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: true, seized: false, seizeRetries: 99))
    }

    /// The Edge powers its touch controller down with the display: while the panel
    /// is asleep/unplugged the digitizer is genuinely unpowered, so churning the
    /// HID manager is futile — wait for the display to return (a display-change
    /// notification reacquires immediately).
    func testPanelAsleepDoesNotChurn() {
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: false, seized: true, seizeRetries: 0))
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: false, displayPresent: false, seized: false, seizeRetries: 0))
    }

    func testHealthyDetectedAndSeizedDoesNothing() {
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: true, seizeRetries: 3))
    }

    func testPresentButNotSeizedRetriesUpToCap() {
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 0))
        XCTAssertTrue(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 4))
        // At the cap: stop churning the panel — macOS won't yield the device.
        XCTAssertFalse(TouchRecoveryPolicy.shouldReacquire(touchOn: true, deviceDetected: true, displayPresent: true, seized: false, seizeRetries: 5))
    }
}
