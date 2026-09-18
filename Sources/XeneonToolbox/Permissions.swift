import AppKit
import AVFoundation
import CoreBluetooth
import CoreLocation
import EventKit
import IOKit.hid
import Speech

/// Everything macOS has to allow before a feature works, with the exact
/// System Settings pane for each and a way to ask that never leaves the user
/// stranded: ask the system first, and when macOS won't show its prompt (it
/// often won't for an app that never comes to the front, or after one decline)
/// open the pane where the switch lives.
enum AppPermission: String, CaseIterable, Identifiable {
    case inputMonitoring, accessibility, calendar, location, microphone, speech, bluetooth

    var id: String { rawValue }

    enum Status: Equatable { case granted, denied, notDetermined }

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        case .calendar: return "Calendar"
        case .location: return "Location"
        case .microphone: return "Microphone"
        case .speech: return "Speech Recognition"
        case .bluetooth: return "Bluetooth"
        }
    }

    /// The card's headline while access is missing.
    var askTitle: String {
        switch self {
        case .inputMonitoring, .accessibility, .speech: return "Allow \(title)"
        default: return "Allow \(title) access"
        }
    }

    /// What the user gets for it, in their words.
    var purpose: String {
        switch self {
        case .inputMonitoring: return "Reads the Edge's touch panel so taps and swipes work."
        case .accessibility: return "Moves app windows onto the Edge and back."
        case .calendar: return "Shows your next events on the dashboard and ambient screen."
        case .location: return "Local weather and the names of nearby Wi-Fi networks."
        case .microphone: return "Talk to the assistant instead of typing."
        case .speech: return "Turns what you say into text, on this Mac."
        case .bluetooth: return "Connect and disconnect your devices from the control centre."
        }
    }

    var icon: String {
        switch self {
        case .inputMonitoring: return "hand.tap.fill"
        case .accessibility: return "macwindow.on.rectangle"
        case .calendar: return "calendar"
        case .location: return "location.fill"
        case .microphone: return "mic.fill"
        case .speech: return "waveform"
        case .bluetooth: return "wave.3.right"
        }
    }

    /// The Privacy & Security pane that holds this switch.
    var settingsURL: URL {
        let pane: String
        switch self {
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .accessibility: pane = "Privacy_Accessibility"
        case .calendar: pane = "Privacy_Calendars"
        case .location: pane = "Privacy_LocationServices"
        case .microphone: pane = "Privacy_Microphone"
        case .speech: pane = "Privacy_SpeechRecognition"
        case .bluetooth: pane = "Privacy_Bluetooth"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    var status: Status {
        switch self {
        case .inputMonitoring:
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            default: return .notDetermined
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .location:
            switch Self.locationManager.authorizationStatus {
            case .authorized, .authorizedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    private static let locationManager = CLLocationManager()
    private static var bluetoothProbe: CBCentralManager?
    private static let eventStore = EKEventStore()

    /// The name `tccutil` knows this service by (Location isn't a TCC service).
    var tccService: String? {
        switch self {
        case .inputMonitoring: return "ListenEvent"
        case .accessibility: return "Accessibility"
        case .calendar: return "Calendar"
        case .microphone: return "Microphone"
        case .speech: return "SpeechRecognition"
        case .bluetooth: return "Bluetooth"
        case .location: return nil
        }
    }

    /// Asks macOS to show its own prompt. Only possible while the answer is still
    /// undecided (and never for Accessibility, which only has the Settings pane).
    /// The completion reports the answer; the prompts that have no callback
    /// report nil.
    func requestFromSystem(completion: @escaping (Bool?) -> Void = { _ in }) {
        switch self {
        case .inputMonitoring: completion(IOHIDRequestAccess(kIOHIDRequestTypeListenEvent))
        case .accessibility:
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            completion(AXIsProcessTrustedWithOptions(opts))
        case .calendar: Self.eventStore.requestFullAccessToEvents { granted, _ in completion(granted) }
        case .location: Self.locationManager.requestWhenInUseAuthorization(); completion(nil)
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { completion($0) }
        case .speech: SFSpeechRecognizer.requestAuthorization { completion($0 == .authorized) }
        case .bluetooth: Self.bluetoothProbe = CBCentralManager(delegate: nil, queue: nil); completion(nil)   // creating one asks
        }
    }

    /// macOS remembers a grant per code signature. A copy of the app signed
    /// differently (an earlier ad-hoc build) leaves a record that no longer
    /// matches this one: System Settings shows the switch on, yet every request
    /// is refused instantly without a prompt and the status never leaves
    /// "not determined". Clearing that record lets the prompt appear again.
    /// Calls back with the final answer.
    func requestRepairingStaleGrant(completion: @escaping (Bool) -> Void) {
        let asked = CFAbsoluteTimeGetCurrent()
        requestFromSystem { granted in
            let instant = CFAbsoluteTimeGetCurrent() - asked < 0.4
            guard granted == false, instant, self.status == .notDetermined, let service = self.tccService,
                  let bundle = Bundle.main.bundleIdentifier else {
                completion(granted ?? (self.status == .granted)); return
            }
            AppLog.info("permissions", "\(self.title): refused without a prompt — clearing the stale grant and asking again")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, bundle]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            self.requestFromSystem { again in completion(again ?? (self.status == .granted)) }
        }
    }

    /// The one-tap flow: bring the app forward so the system prompt can appear,
    /// ask (repairing a stale record if that's what blocks the prompt), and if
    /// macOS still won't ask, open the exact pane.
    @MainActor
    func guide() {
        switch status {
        case .granted:
            return
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            let asked = CFAbsoluteTimeGetCurrent()
            requestRepairingStaleGrant { granted in
                DispatchQueue.main.async {
                    // An instant refusal means no prompt was shown; a slow answer was the user's.
                    if !granted, CFAbsoluteTimeGetCurrent() - asked < 1.0, self.status != .granted { self.openSettings() }
                }
            }
        case .denied:
            openSettings()
        }
    }

    func openSettings() {
        AppLog.info("permissions", "opening System Settings for \(title)")
        NSWorkspace.shared.open(settingsURL)
    }
}
