import XCTest
@testable import ToolboxKit

final class Game2048Tests: XCTestCase {
    func collapse(_ r: [Int]) -> [Int] { Game2048.collapseLeft(r).row }
    func gained(_ r: [Int]) -> Int { Game2048.collapseLeft(r).gained }

    func testSlidesWithoutMerging() {
        XCTAssertEqual(collapse([2, 0, 0, 0]), [2, 0, 0, 0])
        XCTAssertEqual(collapse([0, 0, 0, 2]), [2, 0, 0, 0])
        XCTAssertEqual(collapse([0, 2, 0, 4]), [2, 4, 0, 0])
    }

    func testMergesEqualPair() {
        XCTAssertEqual(collapse([2, 2, 0, 0]), [4, 0, 0, 0])
        XCTAssertEqual(gained([2, 2, 0, 0]), 4)
    }

    func testMergesOnlyOncePerPair() {
        XCTAssertEqual(collapse([2, 2, 2, 2]), [4, 4, 0, 0])
        XCTAssertEqual(gained([2, 2, 2, 2]), 8)
        XCTAssertEqual(collapse([2, 2, 2, 0]), [4, 2, 0, 0])
    }

    func testDoesNotMergeDifferentValues() {
        XCTAssertEqual(collapse([4, 2, 2, 4]), [4, 4, 4, 0])
    }

    func testMoveReportsWhetherBoardChanged() {
        var g = Game2048([[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(g.move(.left))
        XCTAssertEqual(g.grid[0], [4, 0, 0, 0])
        XCTAssertEqual(g.score, 4)
        XCTAssertFalse(g.move(.left)) // already collapsed, no change
    }

    func testMoveUpMergesColumns() {
        var g = Game2048([[2, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(g.move(.up))
        XCTAssertEqual(g.grid[0][0], 4)
    }
}
