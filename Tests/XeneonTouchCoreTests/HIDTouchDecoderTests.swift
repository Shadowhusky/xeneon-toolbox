import XCTest
@testable import XeneonTouchCore

final class HIDTouchDecoderTests: XCTestCase {
    // The real Xeneon Edge reports contact as Button 1 on the Button usage
    // page (0x09/0x01), captured from live `diagnose` output — NOT a digitizer
    // tip switch.
    func testButtonOnePageSignalsContact() {
        var d = HIDTouchDecoder()
        d.ingest(page: 0x09, usage: 0x01, value: 1)
        XCTAssertTrue(d.contact)
        d.ingest(page: 0x09, usage: 0x01, value: 0)
        XCTAssertFalse(d.contact)
    }

    func testGenericDesktopXAndYSetRawCoordinates() {
        var d = HIDTouchDecoder()
        d.ingest(page: 0x01, usage: 0x30, value: 13496)
        d.ingest(page: 0x01, usage: 0x31, value: 4619)
        XCTAssertEqual(d.rawX, 13496)
        XCTAssertEqual(d.rawY, 4619)
    }

    func testWheelAndUnknownUsagesAreIgnored() {
        var d = HIDTouchDecoder()
        d.ingest(page: 0x09, usage: 0x01, value: 1)
        d.ingest(page: 0x01, usage: 0x38, value: -5) // wheel noise
        XCTAssertTrue(d.contact)
        XCTAssertNil(d.rawX)
        XCTAssertNil(d.rawY)
    }
}
