import XCTest
@testable import XeneonTouchCore

final class RawTouchRouterTests: XCTestCase {
    private func contact(_ id: Int, _ x: Double, _ y: Double) -> TouchContact {
        TouchContact(id: id, point: ScreenPoint(x: x, y: y))
    }

    private func router() -> RawTouchRouter {
        var r = RawTouchRouter()
        r.regions = [RawRegion(id: 7, x: 100, y: 100, width: 200, height: 100)]
        return r
    }

    func testWithoutRegionsEverythingIsPointer() {
        var r = RawTouchRouter()
        let out = r.route([contact(0, 10, 10)])
        XCTAssertEqual(out.pointer.count, 1)
        XCTAssertNil(out.raw)
    }

    func testFingerLandingInARegionIsRaw() {
        var r = router()
        let out = r.route([contact(0, 150, 150)])
        XCTAssertTrue(out.pointer.isEmpty)
        XCTAssertEqual(out.raw, [RawTouch(id: 0, region: 7, point: ScreenPoint(x: 150, y: 150))])
    }

    func testFingerKeepsItsSideUntilItLifts() {
        var r = router()
        _ = r.route([contact(0, 150, 150), contact(1, 20, 20)])
        // The raw finger slides out of the region, the pointer finger slides in.
        let out = r.route([contact(0, 500, 500), contact(1, 150, 150)])
        XCTAssertEqual(out.raw?.map(\.id), [0])
        XCTAssertEqual(out.pointer.map(\.id), [1])
    }

    func testLastRawLiftReportsOnceThenGoesQuiet() {
        var r = router()
        _ = r.route([contact(0, 150, 150)])
        XCTAssertEqual(r.route([]).raw, [])
        XCTAssertNil(r.route([]).raw)
    }

    func testReusedContactIdIsRoutedAfresh() {
        var r = router()
        _ = r.route([contact(0, 150, 150)])
        _ = r.route([])
        let out = r.route([contact(0, 20, 20)])
        XCTAssertEqual(out.pointer.map(\.id), [0])
    }

    func testRegionRemovedMidTouchLeavesTheFingerWithNobody() {
        var r = router()
        _ = r.route([contact(0, 150, 150)])
        r.regions = []
        let out = r.route([contact(0, 150, 150)])
        XCTAssertTrue(out.pointer.isEmpty)
        XCTAssertEqual(out.raw, [])
    }

    func testResetTellsWhetherTheAppNeedsAnEmptyReport() {
        var r = router()
        XCTAssertFalse(r.reset())
        _ = r.route([contact(0, 150, 150)])
        XCTAssertTrue(r.reset())
    }
}
