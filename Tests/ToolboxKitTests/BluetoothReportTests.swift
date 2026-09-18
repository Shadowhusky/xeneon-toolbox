import XCTest
@testable import ToolboxKit

final class BluetoothReportTests: XCTestCase {
    private let sample = """
    {"SPBluetoothDataType": [{
      "controller_properties": {"controller_address": "00:00"},
      "device_connected": [
        {"MX Master 3S": {"device_minorType": "Mouse", "device_batteryLevelMain": "85%"}},
        {"AirPods Pro": {"device_minorType": "Headphones", "device_batteryLevelLeft": "72%",
                         "device_batteryLevelRight": "68%", "device_batteryLevelCase": "40%"}}
      ],
      "device_not_connected": [
        {"Magic Trackpad": {"device_minorType": "Magic Trackpad"}},
        {"iPhone": {}}
      ]
    }]}
    """.data(using: .utf8)!

    func testConnectedDevicesComeFirstWithLevels() {
        let devices = BluetoothReport.parse(sample)
        XCTAssertEqual(devices.map(\.name), ["AirPods Pro", "MX Master 3S", "iPhone", "Magic Trackpad"])
        XCTAssertEqual(devices.filter(\.connected).count, 2)
        let pods = devices[0]
        XCTAssertEqual(pods.kind, .headphones)
        XCTAssertEqual(pods.left, 72); XCTAssertEqual(pods.right, 68); XCTAssertEqual(pods.caseLevel, 40)
        XCTAssertEqual(pods.lowest, 68)
        XCTAssertEqual(devices[1].main, 85)
        XCTAssertEqual(devices[1].kind, .mouse)
    }

    func testDevicesWithoutBatteryStillParse() {
        let devices = BluetoothReport.parse(sample)
        let trackpad = devices.first { $0.name == "Magic Trackpad" }!
        XCTAssertEqual(trackpad.kind, .trackpad)
        XCTAssertFalse(trackpad.hasBattery)
        XCTAssertEqual(devices.first { $0.name == "iPhone" }?.kind, .other)
    }

    func testGarbageIsEmpty() {
        XCTAssertEqual(BluetoothReport.parse(Data("nope".utf8)), [])
        XCTAssertEqual(BluetoothReport.percent("  "), nil)
        XCTAssertEqual(BluetoothReport.percent("100%"), 100)
    }
}
