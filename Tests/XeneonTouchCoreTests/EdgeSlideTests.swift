import XCTest
@testable import XeneonTouchCore

final class EdgeSlideTests: XCTestCase {
    func testInwardTravelIsAPullEvenWhenItAlsoMovesSideways() {
        XCTAssertEqual(EdgeSlide.decide(along: 60, inward: 12, startedInBand: true), .pull)
    }

    func testSidewaysTravelInTheBandIsASlide() {
        XCTAssertEqual(EdgeSlide.decide(along: -40, inward: 3, startedInBand: true), .slide)
    }

    func testSidewaysTravelOutsideTheBandStaysUndecided() {
        XCTAssertEqual(EdgeSlide.decide(along: 80, inward: 2, startedInBand: false), .undecided)
    }

    func testADiagonalDragIsNotASlide() {
        XCTAssertEqual(EdgeSlide.decide(along: 36, inward: 20, startedInBand: true, pullActivate: 30), .undecided)
    }

    func testSmallMovesStayUndecided() {
        XCTAssertEqual(EdgeSlide.decide(along: 12, inward: 1, startedInBand: true), .undecided)
    }

    func testValueCoversTheRangeInABitOverHalfTheStrip() {
        XCTAssertEqual(EdgeSlide.value(start: 0.5, travel: 0.11), 0.7, accuracy: 0.0001)
        XCTAssertEqual(EdgeSlide.value(start: 0.2, travel: -0.5), 0)
        XCTAssertEqual(EdgeSlide.value(start: 0.9, travel: 0.5), 1)
    }
}
