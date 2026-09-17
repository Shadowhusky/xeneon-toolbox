import XCTest
@testable import ToolboxKit

final class WebAddressTests: XCTestCase {
    func testPublicDomainDefaultsToHTTPS() {
        XCTAssertEqual(WebAddress.resolve("example.com/docs")?.absoluteString, "https://example.com/docs")
    }

    func testLocalhostWithPortDefaultsToHTTP() {
        XCTAssertEqual(WebAddress.resolve("localhost:3000")?.absoluteString, "http://localhost:3000")
    }

    func testPrivateIPv4DefaultsToHTTP() {
        XCTAssertEqual(WebAddress.resolve("192.168.1.20:8080/status")?.absoluteString,
                       "http://192.168.1.20:8080/status")
    }

    func testExplicitSchemeIsPreserved() {
        XCTAssertEqual(WebAddress.resolve("http://example.com")?.absoluteString, "http://example.com")
    }

    func testWordsBecomeSearchQuery() {
        let url = WebAddress.resolve("xeneon edge mac")
        XCTAssertEqual(URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value, "xeneon edge mac")
    }

    func testWhitespaceOnlyReturnsNil() {
        XCTAssertNil(WebAddress.resolve("   \n"))
    }
}
