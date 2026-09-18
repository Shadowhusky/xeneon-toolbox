import Foundation

/// A Bluetooth peripheral as `system_profiler SPBluetoothDataType -json` reports it.
public struct BluetoothPeripheral: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable { case headphones, mouse, keyboard, trackpad, gamepad, speaker, phone, watch, other }

    public let name: String
    public let kind: Kind
    public let connected: Bool
    /// Charge in percent. Earbuds report left/right/case; everything else main.
    public var main: Int?
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?

    public var id: String { name }
    /// The level that matters for "should I charge this": the emptiest earbud, or the device itself.
    public var lowest: Int? { [main, left, right].compactMap { $0 }.min() }
    public var hasBattery: Bool { lowest != nil || caseLevel != nil }

    public init(name: String, kind: Kind, connected: Bool,
                main: Int? = nil, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil) {
        self.name = name; self.kind = kind; self.connected = connected
        self.main = main; self.left = left; self.right = right; self.caseLevel = caseLevel
    }
}

public enum BluetoothReport {
    /// Parses the profiler's JSON. Connected devices come first, then by name.
    public static func parse(_ data: Data) -> [BluetoothPeripheral] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [BluetoothPeripheral] = []
        for section in sections {
            out += devices(section["device_connected"], connected: true)
            out += devices(section["device_not_connected"], connected: false)
        }
        return out.sorted {
            if $0.connected != $1.connected { return $0.connected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func devices(_ list: Any?, connected: Bool) -> [BluetoothPeripheral] {
        guard let entries = list as? [[String: Any]] else { return [] }
        return entries.flatMap { entry in
            entry.compactMap { name, value -> BluetoothPeripheral? in
                guard let props = value as? [String: Any] else { return nil }
                return BluetoothPeripheral(
                    name: name, kind: kind(props["device_minorType"] as? String), connected: connected,
                    main: percent(props["device_batteryLevelMain"]),
                    left: percent(props["device_batteryLevelLeft"]),
                    right: percent(props["device_batteryLevelRight"]),
                    caseLevel: percent(props["device_batteryLevelCase"]))
            }
        }
    }

    static func kind(_ minorType: String?) -> BluetoothPeripheral.Kind {
        let t = (minorType ?? "").lowercased()
        if t.contains("headphone") || t.contains("headset") || t.contains("earbud") { return .headphones }
        if t.contains("mouse") { return .mouse }
        if t.contains("keyboard") { return .keyboard }
        if t.contains("trackpad") { return .trackpad }
        if t.contains("gamepad") || t.contains("joystick") || t.contains("controller") { return .gamepad }
        if t.contains("speaker") { return .speaker }
        if t.contains("phone") { return .phone }
        if t.contains("watch") { return .watch }
        return .other
    }

    static func percent(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}
