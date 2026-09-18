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

    /// Asks macOS to show its own prompt. Only possible while the answer is still
    /// undecided (and never for Accessibility, which only has the Settings pane).
    func requestFromSystem() {
        switch self {
        case .inputMonitoring: _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .accessibility:
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        case .calendar: Self.eventStore.requestFullAccessToEvents { _, _ in }
        case .location: Self.locationManager.requestWhenInUseAuthorization()
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .speech: SFSpeechRecognizer.requestAuthorization { _ in }
        case .bluetooth: Self.bluetoothProbe = CBCentralManager(delegate: nil, queue: nil)   // creating one asks
        }
    }

    /// The one-tap flow: bring the app forward so the system prompt can appear,
    /// ask, and if nothing was granted shortly after, open the exact pane.
    @MainActor
    func guide() {
        if status == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            requestFromSystem()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.status != .granted { self.openSettings() }
            }
        } else if status == .denied {
            openSettings()
        }
    }

    func openSettings() {
        AppLog.info("permissions", "opening System Settings for \(title)")
        NSWorkspace.shared.open(settingsURL)
    }
}
