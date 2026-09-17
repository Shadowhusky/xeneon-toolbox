import XCTest
@testable import ToolboxKit

final class ClipboardHistoryTests: XCTestCase {
    func testNewestFirstAndCapacity() {
        var h = ClipboardHistory(capacity: 3)
        ["a", "b", "c", "d"].forEach { h.push($0) }
        XCTAssertEqual(h.items, ["d", "c", "b"])
    }

    func testRepeatMovesToFront() {
        var h = ClipboardHistory()
        ["a", "b", "a"].forEach { h.push($0) }
        XCTAssertEqual(h.items, ["a", "b"])
    }

    func testIgnoresBlank() {
        var h = ClipboardHistory()
        h.push("  \n")
        XCTAssertTrue(h.items.isEmpty)
    }

    func testRemoveAt() {
        var h = ClipboardHistory()
        ["a", "b"].forEach { h.push($0) }
        h.remove(at: 0)
        XCTAssertEqual(h.items, ["a"])
        h.remove(at: 5)
        XCTAssertEqual(h.items, ["a"])
    }
}
