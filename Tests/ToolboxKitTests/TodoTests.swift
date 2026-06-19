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

    func testAdvanceDailyFromFutureGoesOneDayLater() {
        let due = Date(timeIntervalSinceNow: 3600)   // 1h from now
        let item = TodoItem(title: "standup", dueAt: due, recurrence: .daily)
        let next = item.advanced()
        XCTAssertEqual(next.dueAt!.timeIntervalSince(due), 86_400, accuracy: 3600)  // ~+1 day
        XCTAssertFalse(next.done)
        XCTAssertTrue(next.dueAt! > Date())
    }

    func testAdvanceWeeklyFromOverdueLandsInFuture() {
        let due = Date(timeIntervalSinceNow: -10 * 86_400)   // 10 days ago, weekly
        let item = TodoItem(title: "review", dueAt: due, recurrence: .weekly)
        let next = item.advanced()
        XCTAssertTrue(next.dueAt! > Date(), "advanced recurring due must be in the future")
    }

    func testAdvanceNonRecurringIsNoOp() {
        let item = TodoItem(title: "once", dueAt: Date(), recurrence: .none)
        XCTAssertEqual(item.advanced(), item)
    }

    func testRecurrenceDecodesMissingFieldAsNone() throws {
        // Old saved JSON without a recurrence field must still decode.
        let json = #"{"id":"\#(UUID().uuidString)","title":"old","done":false,"createdAt":0}"#
        let item = try JSONDecoder().decode(TodoItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.recurrence, .none)
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
