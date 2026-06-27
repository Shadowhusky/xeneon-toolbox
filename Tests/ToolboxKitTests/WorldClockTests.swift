import XCTest
@testable import ToolboxKit

final class WorldClockTests: XCTestCase {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, tz: String = "UTC") -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: c)!
    }

    func testOffsetLabel() {
        let utc = TimeZone(identifier: "UTC")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let ny = TimeZone(identifier: "America/New_York")!
        let d = date(2024, 1, 15, 12, 0)
        XCTAssertEqual(WorldClockInfo.offsetLabel(of: tokyo, from: utc, at: d), "+9h")
        XCTAssertEqual(WorldClockInfo.offsetLabel(of: ny, from: utc, at: d), "-5h")   // EST
        XCTAssertEqual(WorldClockInfo.offsetLabel(of: utc, from: utc, at: d), "same")
    }

    func testHalfHourOffset() {
        let utc = TimeZone(identifier: "UTC")!
        let india = TimeZone(identifier: "Asia/Kolkata")!   // +5:30
        XCTAssertEqual(WorldClockInfo.offsetLabel(of: india, from: utc, at: date(2024, 1, 15, 12, 0)), "+5:30")
    }

    func testIsDaytime() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertTrue(WorldClockInfo.isDaytime(in: utc, at: date(2024, 1, 15, 12, 0)))
        XCTAssertFalse(WorldClockInfo.isDaytime(in: utc, at: date(2024, 1, 15, 2, 0)))
        XCTAssertFalse(WorldClockInfo.isDaytime(in: utc, at: date(2024, 1, 15, 22, 0)))
    }

    func testDayDeltaAndLabel() {
        let utc = TimeZone(identifier: "UTC")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let d = date(2024, 1, 15, 20, 0)   // UTC 20:00 → Tokyo +1 day, LA same day
        XCTAssertEqual(WorldClockInfo.dayDelta(of: tokyo, from: utc, at: d), 1)
        XCTAssertEqual(WorldClockInfo.dayLabel(of: tokyo, from: utc, at: d), "Tomorrow")
        XCTAssertEqual(WorldClockInfo.dayDelta(of: utc, from: utc, at: d), 0)
        XCTAssertNil(WorldClockInfo.dayLabel(of: la, from: utc, at: d))
    }

    func testCatalogResolve() {
        XCTAssertEqual(WorldCityCatalog.resolve("tokyo")?.timeZoneID, "Asia/Tokyo")
        XCTAssertEqual(WorldCityCatalog.resolve("Paris")?.timeZoneID, "Europe/Paris")
        XCTAssertEqual(WorldCityCatalog.resolve("Asia/Dubai")?.timeZoneID, "Asia/Dubai")  // raw tz id
        XCTAssertNil(WorldCityCatalog.resolve("Atlantis"))
    }

    func testCatalogSearch() {
        XCTAssertTrue(WorldCityCatalog.search("york").contains { $0.name == "New York" })
        XCTAssertEqual(WorldCityCatalog.search("").count, WorldCityCatalog.all.count)
        XCTAssertTrue(WorldCityCatalog.search("zzzz").isEmpty)
    }
}
