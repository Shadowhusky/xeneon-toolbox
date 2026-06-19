import XCTest
@testable import ToolboxKit

final class AgentDataParsingTests: XCTestCase {

    // MARK: rows

    func testRowsFrom2DArray() {
        let raw: [Any] = [["Mercury", "4,879", "0"], ["Venus", "12,104", "0"]]
        XCTAssertEqual(AgentDataParsing.rows(from: raw),
                       [["Mercury", "4,879", "0"], ["Venus", "12,104", "0"]])
    }

    func testRowsFromArrayOfPipeStrings() {
        let raw: [Any] = ["Mercury | 4879 | 0", "Venus | 12104 | 0"]
        XCTAssertEqual(AgentDataParsing.rows(from: raw),
                       [["Mercury", "4879", "0"], ["Venus", "12104", "0"]])
    }

    func testRowsCoercesNumbersToStrings() {
        let raw: [Any] = [["Earth", 12756, 1]]
        XCTAssertEqual(AgentDataParsing.rows(from: raw), [["Earth", "12756", "1"]])
    }

    /// Regression: the local Qwen model emitted `rows` as a string that is a
    /// JSON 2D array missing its leading bracket. It must be repaired, and
    /// quoted commas inside cells must be preserved.
    func testRowsRepairsMalformedJSONString() {
        let malformed = "[\"Mercury\", \"4,879\", \"0\"], [\"Venus\", \"12,104\", \"0\"], [\"Earth\", \"12,756\", \"1\"]]"
        XCTAssertEqual(AgentDataParsing.rows(from: malformed),
                       [["Mercury", "4,879", "0"], ["Venus", "12,104", "0"], ["Earth", "12,756", "1"]])
    }

    func testRowsFromValidJSONString() {
        let json = "[[\"a\", \"b\"], [\"c\", \"d\"]]"
        XCTAssertEqual(AgentDataParsing.rows(from: json), [["a", "b"], ["c", "d"]])
    }

    func testRowsFromNilOrJunk() {
        XCTAssertEqual(AgentDataParsing.rows(from: nil), [])
        XCTAssertEqual(AgentDataParsing.rows(from: 42), [])
    }

    // MARK: cells

    func testCellsFromArray() {
        XCTAssertEqual(AgentDataParsing.cells(from: ["Planet", "Diameter", "Moons"]),
                       ["Planet", "Diameter", "Moons"])
    }

    func testCellsFromPipeString() {
        XCTAssertEqual(AgentDataParsing.cells(from: "a | b | c"), ["a", "b", "c"])
    }

    func testCellsFromCommaString() {
        XCTAssertEqual(AgentDataParsing.cells(from: "a, b, c"), ["a", "b", "c"])
    }

    // MARK: labelValue

    func testLabelValueFromString() {
        let lv = AgentDataParsing.labelValue(from: "BTC: 65000")
        XCTAssertEqual(lv.label, "BTC")
        XCTAssertEqual(lv.value, "65000")
    }

    func testLabelValueFromLabelObject() {
        let lv = AgentDataParsing.labelValue(from: ["label": "USA", "value": 331])
        XCTAssertEqual(lv.label, "USA")
        XCTAssertEqual(lv.value, "331")
    }

    func testLabelValueFromNameObject() {
        let lv = AgentDataParsing.labelValue(from: ["name": "ETH", "value": 3500.5])
        XCTAssertEqual(lv.label, "ETH")
        XCTAssertEqual(lv.value, "3500.5")
    }

    func testLabelValueStringWithoutColon() {
        let lv = AgentDataParsing.labelValue(from: "Just a label")
        XCTAssertEqual(lv.label, "Just a label")
        XCTAssertEqual(lv.value, "")
    }
}
