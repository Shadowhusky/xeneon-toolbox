import XCTest
@testable import ToolboxKit

final class UpdateStrategyTests: XCTestCase {
    func testVersionCompareIsNumericNotLexical() {
        XCTAssertEqual(UpdateStrategy.compare("1.10.0", "1.9.0"), 1)
        XCTAssertEqual(UpdateStrategy.compare("1.17.0", "1.17"), 0)
        XCTAssertEqual(UpdateStrategy.compare("1.17.1", "1.18.0"), -1)
        XCTAssertEqual(UpdateStrategy.compare("2.0.0-beta", "2.0.0"), 0)
    }

    func testNormalizeStripsTagPrefix() {
        XCTAssertEqual(UpdateStrategy.normalize("v1.18.0"), "1.18.0")
        XCTAssertEqual(UpdateStrategy.normalize(" 1.18.0 "), "1.18.0")
    }

    func testQuietMomentNeedsIdleAndNothingInFlight() {
        XCTAssertFalse(UpdateStrategy.isQuietMoment(idleSeconds: 3600, interacting: true, fullUI: false))
        XCTAssertFalse(UpdateStrategy.isQuietMoment(idleSeconds: 300, interacting: false, fullUI: false))
        XCTAssertTrue(UpdateStrategy.isQuietMoment(idleSeconds: 600, interacting: false, fullUI: false))
        // The full UI is visible, so a relaunch waits for a longer lull.
        XCTAssertFalse(UpdateStrategy.isQuietMoment(idleSeconds: 600, interacting: false, fullUI: true))
        XCTAssertTrue(UpdateStrategy.isQuietMoment(idleSeconds: 1800, interacting: false, fullUI: true))
    }

    func testCheckDelayJitterStaysWithinTenPercent() {
        XCTAssertEqual(UpdateStrategy.nextCheckDelay(base: 1000, random: 0), 900, accuracy: 0.001)
        XCTAssertEqual(UpdateStrategy.nextCheckDelay(base: 1000, random: 1), 1100, accuracy: 0.001)
        XCTAssertEqual(UpdateStrategy.nextCheckDelay(base: 1000, random: 7), 1100, accuracy: 0.001)
    }
}
