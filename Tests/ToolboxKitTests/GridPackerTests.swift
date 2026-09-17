import XCTest
@testable import ToolboxKit

final class GridPackerTests: XCTestCase {
    func testTallTileTakesBothRowsAndNextTilesFlowRight() {
        let r = GridPacker.pack([PackedItem(id: "clock", columns: 1, rows: 2),
                                 PackedItem(id: "cpu", columns: 1, rows: 1),
                                 PackedItem(id: "gpu", columns: 1, rows: 1)], columns: 8, rows: 2)
        XCTAssertEqual(r.placed["clock"], GridSlot(column: 0, row: 0, columns: 1, rows: 2))
        XCTAssertEqual(r.placed["cpu"], GridSlot(column: 1, row: 0, columns: 1, rows: 1))
        XCTAssertEqual(r.placed["gpu"], GridSlot(column: 2, row: 0, columns: 1, rows: 1))
    }

    func testWideTileSkipsAColumnItCannotFit() {
        // 7 singles on the top row leave one free column; a wide tile must go to row 1.
        var items = (0..<7).map { PackedItem(id: "s\($0)", columns: 1, rows: 1) }
        items.append(PackedItem(id: "wide", columns: 2, rows: 1))
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertEqual(r.placed["wide"], GridSlot(column: 0, row: 1, columns: 2, rows: 1))
    }

    func testLaterSmallTileBackfillsTheGap() {
        var items = (0..<7).map { PackedItem(id: "s\($0)", columns: 1, rows: 1) }
        items.append(PackedItem(id: "wide", columns: 2, rows: 1))
        items.append(PackedItem(id: "late", columns: 1, rows: 1))
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertEqual(r.placed["late"], GridSlot(column: 7, row: 0, columns: 1, rows: 1))
    }

    func testOverflowKeepsOrder() {
        let items = (0..<18).map { PackedItem(id: $0, columns: 1, rows: 1) }
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertEqual(r.placed.count, 16)
        XCTAssertEqual(r.overflow, [16, 17])
    }

    func testDefaultBoardFillsExactlySixteenCells() {
        let items = [PackedItem(id: "clock", columns: 1, rows: 2), PackedItem(id: "cpu", columns: 1, rows: 1),
                     PackedItem(id: "gpu", columns: 1, rows: 1), PackedItem(id: "memory", columns: 1, rows: 1),
                     PackedItem(id: "network", columns: 2, rows: 1), PackedItem(id: "storage", columns: 1, rows: 1),
                     PackedItem(id: "power", columns: 1, rows: 1), PackedItem(id: "upNext", columns: 2, rows: 1),
                     PackedItem(id: "tasks", columns: 1, rows: 1), PackedItem(id: "thermals", columns: 1, rows: 1),
                     PackedItem(id: "dock", columns: 2, rows: 1), PackedItem(id: "nowPlaying", columns: 1, rows: 1)]
        let r = GridPacker.pack(items, columns: 8, rows: 2)
        XCTAssertTrue(r.overflow.isEmpty)
        XCTAssertEqual(r.placed.values.reduce(0) { $0 + $1.columns * $1.rows }, 16)
    }
}
