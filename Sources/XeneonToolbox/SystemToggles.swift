import AppKit
import Foundation
import CoreLocation
import CoreWLAN
import IOBluetooth

// Bluetooth power: the same private IOBluetooth preference calls blueutil uses —
// there is no public API for the system controller's power state.
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
private func IOBluetoothPreferenceGetControllerPowerState() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
private func IOBluetoothPreferenceSetControllerPowerState(_ state: Int32)

struct WifiNetwork: Identifiable, Equatable {
    let ssid: String
    let rssi: Int
    let secure: Bool
    let current: Bool
    var id: String { ssid }
}

struct BluetoothDevice: Identifiable, Equatable {
    let name: String
    let address: String
    let connected: Bool
    let symbol: String
    var id: String { address }
}

struct FocusMode: Identifiable, Equatable {
    let name: String
    let identifier: String
    let active: Bool
    var id: String { identifier }
}

/// Wi-Fi, Bluetooth, and Focus for the Control Centre — read fast, toggle
/// best-effort, and re-read after a beat so the tiles reflect what the system
/// actually did. Mirrors macOS Control Centre: the icon toggles power, the tile
/// expands into a network / device picker.
@MainActor
final class SystemToggles: ObservableObject {
    @Published private(set) var wifiOn = false
    @Published private(set) var wifiName: String?
    @Published private(set) var btOn = false
    @Published private(set) var focusOn = false
    @Published private(set) var focusAvailable = true   // a "Toggle Focus" shortcut exists

    @Published private(set) var wifiPresent = true   // this Mac has a Wi-Fi interface
    @Published private(set) var wifiNetworks: [WifiNetwork] = []
    @Published private(set) var wifiScanning = false
    @Published private(set) var wifiNamesRedacted = false   // scan found networks but macOS hid the names
    @Published private(set) var wifiBusy: String?    // ssid with a join/leave in flight
    @Published private(set) var wifiError: String?
    @Published private(set) var btDevices: [BluetoothDevice] = []
    @Published private(set) var btBusy: String?      // device address in flight
    @Published private(set) var btError: String?
    @Published private(set) var focusModes: [FocusMode] = []
    @Published private(set) var focusAccess = true   // Focus DB is Full-Disk-Access gated
    @Published private(set) var darkMode = false

    private var shortcutNames: Set<String> = []
    private var checkedShortcut = false

    func refresh() {
        let wifi = CWWiFiClient.shared().interface()
        wifiPresent = wifi != nil
        wifiOn = wifi?.powerOn() ?? false
        btOn = IOBluetoothPreferenceGetControllerPowerState() == 1
        focusAccess = FileManager.default.isReadableFile(
            atPath: Self.dndDir.appendingPathComponent("Assertions.json").path)
        focusOn = Self.focusActive()
        darkMode = (CFPreferencesCopyValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String) == "Dark"
        Task { [weak self] in   // SSID via CoreWLAN needs Location; networksetup doesn't
            let name = await Task.detached { Self.currentSSID() }.value
            self?.wifiName = name
        }
        if !checkedShortcut {
            checkedShortcut = true
            Task { [weak self] in
                let names = await Task.detached { Self.listShortcuts() }.value
                self?.shortcutNames = names
                self?.focusAvailable = names.contains("Toggle Focus")
            }
        }
    }

    /// The joined network's name: CoreWLAN when Location access allows it,
    /// otherwise networksetup (which is not redacted).
    private nonisolated static func currentSSID() -> String? {
        if let ssid = CWWiFiClient.shared().interface()?.ssid() { return ssid }
        let device = CWWiFiClient.shared().interface()?.interfaceName ?? "en0"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-getairportnetwork", device]
        let pipe = Pipe(); p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let range = out.range(of: "Current Wi-Fi Network: ") else { return nil }
        let name = out[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func setWifi(_ on: Bool) {
        wifiOn = on   // optimistic; verified below
        if let interface = CWWiFiClient.shared().interface() {
            try? interface.setPower(on)
        }
        AppLog.info("controls", "Wi-Fi \(on ? "on" : "off")")
        reverify()
    }

    func setBluetooth(_ on: Bool) {
        btOn = on
        IOBluetoothPreferenceSetControllerPowerState(on ? 1 : 0)
        AppLog.info("controls", "Bluetooth \(on ? "on" : "off")")
        reverify()
    }

    /// Focus has no public toggle API — run the user's "Toggle Focus" shortcut
    /// (one built-in "Set Focus" action in Shortcuts). Without it, take them to
    /// the Shortcuts app instead of silently doing nothing.
    func toggleFocus() {
        guard focusAvailable else {
            AppLog.info("controls", "Focus needs a 'Toggle Focus' shortcut — opening Shortcuts")
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            return
        }
        focusOn.toggle()   // optimistic
        runShortcut("Toggle Focus")
        reverify(after: 1.2)
    }

    /// The user's Focus modes (Do Not Disturb, Work, Sleep…), active one marked —
    /// read from the same store macOS's own Control Centre uses. That store is
    /// Full-Disk-Access gated; without the grant, fall back to a plain Do Not
    /// Disturb row and let the picker explain.
    func loadFocusModes() {
        focusAccess = FileManager.default.isReadableFile(
            atPath: Self.dndDir.appendingPathComponent("Assertions.json").path)
        let activeIDs = Self.activeFocusIdentifiers()
        var modes = Self.configuredFocusModes().map {
            FocusMode(name: $0.name, identifier: $0.identifier, active: activeIDs.contains($0.identifier))
        }
        if modes.isEmpty {
            modes = [FocusMode(name: "Do Not Disturb", identifier: "com.apple.donotdisturb.mode.default", active: focusOn)]
        }
        focusModes = modes
    }

    /// Focus state and mode names live behind Full Disk Access — send the user
    /// straight to the right Privacy pane.
    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Activate a mode: run a Shortcut with the mode's own name if the user made
    /// one, else fall back to "Toggle Focus", else open Shortcuts to set it up.
    func activateFocus(_ mode: FocusMode) {
        if shortcutNames.contains(mode.name) {
            runShortcut(mode.name)
        } else if focusAvailable {
            runShortcut("Toggle Focus")
        } else {
            AppLog.info("controls", "no shortcut for Focus mode '\(mode.name)' — opening Shortcuts")
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refresh()
            self?.loadFocusModes()
        }
    }

    /// System-wide appearance toggle (asks for Automation consent to System
    /// Events on first use — the supported route to the appearance setting).
    func setDarkMode(_ on: Bool) {
        darkMode = on   // optimistic
        AppLog.info("controls", "dark mode \(on ? "on" : "off")")
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"]
            try? p.run()
            p.waitUntilExit()
        }
        reverify(after: 1.0)
    }

    private func runShortcut(_ name: String) {
        AppLog.info("controls", "run shortcut '\(name)'")
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", name]
            try? p.run()
            p.waitUntilExit()
        }
    }

    private func reverify(after seconds: Double = 0.8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.refresh() }
    }

    // MARK: - Wi-Fi network picker

    /// Scan for nearby networks (a few seconds, off the main thread). Shows ONLY
    /// what the scan discovers: macOS redacts SSIDs unless Location access is
    /// granted, and in that case the picker explains and offers the grant instead
    /// of showing a misleading saved-networks list.
    func scanWifi() {
        guard !wifiScanning else { return }
        wifiScanning = true
        Task { [weak self] in
            let (found, redacted): ([WifiNetwork], Bool) = await Task.detached {
                guard let interface = CWWiFiClient.shared().interface() else { return ([], false) }
                let current = Self.currentSSID()
                let results = (try? interface.scanForNetworks(withSSID: nil)) ?? []
                var best: [String: WifiNetwork] = [:]
                for n in results {
                    guard let ssid = n.ssid, !ssid.isEmpty else { continue }
                    let net = WifiNetwork(ssid: ssid, rssi: n.rssiValue,
                                          secure: n.supportsSecurity(.wpa2Personal) || n.supportsSecurity(.wpa3Personal) || n.supportsSecurity(.wpaPersonal),
                                          current: ssid == current)
                    if let existing = best[ssid], existing.rssi >= net.rssi { continue }
                    best[ssid] = net
                }
                let nets = best.values.sorted { ($0.current ? 1 : 0, $0.rssi) > ($1.current ? 1 : 0, $1.rssi) }
                return (nets, nets.isEmpty && !results.isEmpty)
            }.value
            self?.wifiNetworks = found
            self?.wifiNamesRedacted = redacted
            self?.wifiScanning = false
            if redacted { AppLog.info("controls", "Wi-Fi scan names redacted — Location access not granted") }
        }
    }

    /// Ask for Location access (unlocks network names). macOS often refuses to
    /// show the consent prompt for an app that never activates, so if it stays
    /// undecided we open the Privacy pane where the switch can be flipped by hand.
    func requestLocationAccess() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (status == .notDetermined ? 2.0 : 0)) { [weak self] in
            guard let self, locationManager.authorizationStatus == .notDetermined || locationManager.authorizationStatus == .denied,
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
            NSWorkspace.shared.open(url)
        }
    }
    private let locationManager = CLLocationManager()

    /// Tap semantics like macOS: the connected network disconnects, any other
    /// network connects.
    func toggleWifiNetwork(_ net: WifiNetwork) {
        guard wifiBusy == nil else { return }
        if net.current { disconnectWifi(net.ssid) } else { joinWifi(net.ssid) }
    }

    private func disconnectWifi(_ ssid: String) {
        AppLog.info("controls", "disconnect Wi-Fi \(ssid)")
        wifiBusy = ssid
        wifiError = nil
        Task { [weak self] in
            await Task.detached { CWWiFiClient.shared().interface()?.disassociate() }.value
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.finishWifiAction(expected: nil, failureText: nil)
        }
    }

    /// Join a network: prefer a direct CoreWLAN associate on a fresh scan match
    /// (uses saved credentials), fall back to networksetup, and SAY SO when both
    /// fail — a dead tap is indistinguishable from a broken button.
    private func joinWifi(_ ssid: String) {
        AppLog.info("controls", "join Wi-Fi \(ssid)")
        wifiBusy = ssid
        wifiError = nil
        Task { [weak self] in
            let errorText: String? = await Task.detached { () -> String? in
                guard let interface = CWWiFiClient.shared().interface() else { return "No Wi-Fi interface" }
                var lastError = "Couldn't join “\(ssid)”"
                if let network = (try? interface.scanForNetworks(withSSID: nil))?
                    .filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
                    do {
                        try interface.associate(to: network, password: nil)
                        return nil
                    } catch {
                        AppLog.error("controls", "associate \(ssid): \(error.localizedDescription)")
                        lastError = "Couldn't join “\(ssid)” — it may be out of range or need its password again"
                    }
                }
                let device = interface.interfaceName ?? "en0"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                p.arguments = ["-setairportnetwork", device, ssid]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                guard (try? p.run()) != nil else { return lastError }
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }   // silence = joined
                AppLog.error("controls", "networksetup join \(ssid): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
                return lastError
            }.value
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // let the association settle
            self?.finishWifiAction(expected: ssid, failureText: errorText)
        }
    }

    /// Re-read the association, update row highlights in place (no slow rescan),
    /// and surface an error when the result doesn't match the intent.
    private func finishWifiAction(expected: String?, failureText: String?) {
        Task { [weak self] in
            let current = await Task.detached { Self.currentSSID() }.value
            guard let self else { return }
            wifiBusy = nil
            wifiName = current
            wifiNetworks = wifiNetworks.map {
                WifiNetwork(ssid: $0.ssid, rssi: $0.rssi, secure: $0.secure, current: $0.ssid == current)
            }
            if let failureText, current != expected {
                wifiError = failureText
            } else if let expected, current != expected {
                wifiError = "Couldn't join “\(expected)”"
            } else {
                wifiError = nil
            }
            refresh()
        }
    }


    // MARK: - Bluetooth device picker

    /// Paired devices with live connection state (same list the menu bar shows).
    func loadBluetoothDevices() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        btDevices = devices.compactMap { d in
            guard let name = d.name ?? d.addressString else { return nil }
            return BluetoothDevice(name: name,
                                   address: d.addressString ?? name,
                                   connected: d.isConnected(),
                                   symbol: Self.deviceSymbol(d))
        }
        .sorted { a, b in
            if a.connected != b.connected { return a.connected }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func toggleBluetoothDevice(_ device: BluetoothDevice) {
        guard btBusy == nil else { return }
        AppLog.info("controls", "\(device.connected ? "disconnect" : "connect") BT \(device.name)")
        btBusy = device.address
        btError = nil
        Task { [weak self] in
            let address = device.address
            let connect = !device.connected
            let ok = await Task.detached { () -> Bool in
                guard let d = IOBluetoothDevice(addressString: address) else { return false }
                if connect { return d.openConnection() == kIOReturnSuccess }
                return d.closeConnection() == kIOReturnSuccess
            }.value
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            btBusy = nil
            if !ok {
                btError = connect
                    ? "Couldn't connect to \(device.name) — is it on and in range?"
                    : "Couldn't disconnect \(device.name)"
            }
            loadBluetoothDevices()
        }
    }

    private static func deviceSymbol(_ d: IOBluetoothDevice) -> String {
        switch Int(d.deviceClassMajor) {
        case 0x04: return "headphones"          // audio
        case 0x05:                              // peripheral: keyboard / mouse bits
            let minor = Int(d.deviceClassMinor)
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse.fill" }
            return "gamecontroller.fill"
        case 0x02: return "iphone"              // phone
        case 0x01: return "laptopcomputer"      // computer
        default: return "wave.3.right"
        }
    }

    /// Focus state: macOS records active Focus assertions in a user-readable
    /// JSON; any store assertion record means a Focus mode is on.
    private static func focusActive() -> Bool {
        !activeFocusIdentifiers().isEmpty
    }

    private static var dndDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    }

    /// Identifiers of the Focus modes currently asserted (usually zero or one).
    private static func activeFocusIdentifiers() -> Set<String> {
        guard let data = try? Data(contentsOf: dndDir.appendingPathComponent("Assertions.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return [] }
        var ids = Set<String>()
        for entry in entries {
            for record in (entry["storeAssertionRecords"] as? [[String: Any]]) ?? [] {
                if let details = record["assertionDetails"] as? [String: Any],
                   let id = details["assertionDetailsModeIdentifier"] as? String {
                    ids.insert(id)
                } else {
                    ids.insert("com.apple.donotdisturb.mode.default")   // assertion without detail = DND
                }
            }
        }
        return ids
    }

    /// The user's configured Focus modes (name + identifier), from macOS's own
    /// mode-configuration store. Parsed defensively — the exact nesting shifts
    /// between macOS versions.
    private static func configuredFocusModes() -> [(name: String, identifier: String)] {
        guard let data = try? Data(contentsOf: dndDir.appendingPathComponent("ModeConfigurations.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return [] }
        var out: [(String, String)] = []
        for entry in entries {
            guard let configs = entry["modeConfigurations"] as? [String: Any] else { continue }
            for (identifier, value) in configs {
                guard let config = value as? [String: Any],
                      let mode = config["mode"] as? [String: Any],
                      let name = mode["name"] as? String, !name.isEmpty else { continue }
                out.append((name, identifier))
            }
        }
        return out.sorted {
            if ($0.1 == "com.apple.donotdisturb.mode.default") != ($1.1 == "com.apple.donotdisturb.mode.default") {
                return $0.1 == "com.apple.donotdisturb.mode.default"   // DND first, like macOS
            }
            return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
    }

    private nonisolated static func listShortcuts() -> Set<String> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Set(out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
