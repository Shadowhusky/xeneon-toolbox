import XCTest
@testable import ToolboxKit

final class TodoTests: XCTestCase {
    private let items = [
        TodoItem(title: "Buy milk"),
        TodoItem(title: "Email Sarah", done: true),
        TodoItem(title: "Email the landlord"),
    ]

    func testResolveByIndex() {
        XCTAssertEqual(TodoMatch.resolve("1", in: items)?.title, "Buy milk")
        XCTAssertEqual(TodoMatch.resolve("3", in: items)?.title, "Email the landlord")
    }

    func testIndexOutOfRangeFallsThroughToText() {
        XCTAssertNil(TodoMatch.resolve("9", in: items))   // "9" isn't a title either
    }

    func testResolveByExactTitleCaseInsensitive() {
        XCTAssertEqual(TodoMatch.resolve("buy milk", in: items)?.title, "Buy milk")
    }

    func testResolveBySubstringPrefersOpenItem() {
        // "email" matches both, but the open one (landlord) is preferred over the done one.
        XCTAssertEqual(TodoMatch.resolve("email", in: items)?.title, "Email the landlord")
    }

    func testNoMatch() {
        XCTAssertNil(TodoMatch.resolve("dentist", in: items))
        XCTAssertNil(TodoMatch.resolve("", in: items))
    }

    func testOverdue() {
        let past = TodoItem(title: "late", dueAt: Date(timeIntervalSinceNow: -3600))
        let future = TodoItem(title: "soon", dueAt: Date(timeIntervalSinceNow: 3600))
        let doneLate = TodoItem(title: "done", done: true, dueAt: Date(timeIntervalSinceNow: -3600))
        XCTAssertTrue(past.isOverdue)
        XCTAssertFalse(future.isOverdue)
        XCTAssertFalse(doneLate.isOverdue)   // done items are never overdue
    }
}
