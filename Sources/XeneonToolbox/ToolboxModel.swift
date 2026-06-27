import SwiftUI
import XeneonTouchDriver
import ToolboxKit

enum DisplayMode { case full, minimal, sleep }

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard, clock, tasks, games, chat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .clock: return "Clock"
        case .tasks: return "Tasks"
        case .games: return "Games"
        case .chat: return "Assistant"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .clock: return "clock.fill"
        case .tasks: return "checklist"
        case .games: return "gamecontroller.fill"
        case .chat: return "sparkles"
        }
    }
    /// Per-destination accent so the active app lights up in its own hue.
    var accent: Color {
        switch self {
        case .dashboard: return Theme.accent
        case .clock: return Theme.time
        case .tasks: return Theme.netUp
        case .games: return Theme.gpu
        case .chat: return Theme.memory
        }
    }
}

/// Owns the embedded touch driver, the metrics engine, and app navigation.
/// Touch works while the app runs; toggling it is just start/stop — no system
/// changes.
@MainActor
final class ToolboxModel: ObservableObject {
    let metrics = SystemMetrics()
    let weather = WeatherService()
    let todos = TodoStore()
    let worldClocks = WorldClockStore()
    let canControlBacklight = Backlight.isAvailable
    @Published var brightness: Int = 90          // Edge backlight 0–100 (DDC)
    private var preDimBrightness = 90             // restored when waking from sleep
    lazy var agent = AgentController(config: ChatConfig.loadSaved() ?? ChatConfig.presets[0].config, app: self)
    @Published var route: AppRoute = .dashboard
    @Published var displayMode: DisplayMode = .minimal   // ambient default; tap to wake to full
    @Published var showSettings = false
    var exportMode = false   // static input bar etc. for off-screen mockup renders
    @Published var touchOn = false
    @Published var edgeDetected = false
    @Published var gamePref = "shanhai"   // "shanhai" | "rhythm"

    // Touch calibration — flips persist and rebuild the driver when changed.
    @Published var flipX = UserDefaults.standard.bool(forKey: "touch.flipX") { didSet { applyCalibration() } }
    @Published var flipY = UserDefaults.standard.bool(forKey: "touch.flipY") { didSet { applyCalibration() } }
    @Published var swapXY = UserDefaults.standard.bool(forKey: "touch.swapXY") { didSet { applyCalibration() } }

    /// Sleep stops monitoring (saves battery, avoids burn-in); minimal keeps
    /// light stats; full is the normal UI.
    func setDisplay(_ mode: DisplayMode) {
        let wasSleep = (displayMode == .sleep)
        if mode == .sleep {
            metrics.stop(); weather.stop()
            dimBacklightForSleep()              // LCD: actually cut the backlight to save power
        } else {
            metrics.start(); weather.start()
            if wasSleep { restoreBacklight() }
        }
        displayMode = mode
    }

    /// Move the screen to sleep with the backlight off (the real power-saving "off").
    func turnScreenOff() { setDisplay(.sleep) }

    func applyBrightness(_ value: Int) {
        let v = max(0, min(100, value))
        brightness = v
        preDimBrightness = v
        guard canControlBacklight else { return }
        DispatchQueue.global(qos: .utility).async { Backlight.setBrightness(v) }
    }

    private func dimBacklightForSleep() {
        guard canControlBacklight else { return }
        let keep = brightness
        DispatchQueue.global(qos: .utility).async {
            let cur = Backlight.getBrightness() ?? keep
            DispatchQueue.main.async { self.preDimBrightness = cur }
            Backlight.setBrightness(0)
        }
    }

    private func restoreBacklight() {
        guard canControlBacklight else { return }
        let target = preDimBrightness > 0 ? preDimBrightness : 90
        DispatchQueue.global(qos: .utility).async { Backlight.setBrightness(target) }
    }

    /// Don't leave the panel dark if the app quits while asleep.
    func restoreBacklightOnQuit() {
        guard canControlBacklight, displayMode == .sleep else { return }
        Backlight.setBrightness(preDimBrightness > 0 ? preDimBrightness : 90)
    }

    private lazy var touch: TouchService = makeTouch()
    private var retryTimer: Timer?

    private func makeTouch() -> TouchService {
        let t = TouchService(config: TouchServiceConfig(flipX: flipX, flipY: flipY, swapXY: swapXY, preferSeize: true))
        t.onPresenceChanged = { [weak self] present in Task { @MainActor in self?.edgeDetected = present } }
        return t
    }

    private func applyCalibration() {
        UserDefaults.standard.set(flipX, forKey: "touch.flipX")
        UserDefaults.standard.set(flipY, forKey: "touch.flipY")
        UserDefaults.standard.set(swapXY, forKey: "touch.swapXY")
        let wasOn = touchOn
        touch.stop()
        edgeDetected = false
        touch = makeTouch()
        if wasOn { startTouch() }
    }

    /// What the touch control shows: Active (driving the panel), Searching
    /// (wants touch but hasn't acquired the digitizer yet), or Off.
    enum TouchStatus { case active, searching, off }
    var touchStatus: TouchStatus { !touchOn ? .off : (edgeDetected ? .active : .searching) }

    init() {
        if let r = ProcessInfo.processInfo.environment["XENEON_ROUTE"],
           let route = AppRoute(rawValue: r) {
            self.route = route
        }
        switch ProcessInfo.processInfo.environment["XENEON_DISPLAY"] {
        case "minimal": displayMode = .minimal
        case "sleep": displayMode = .sleep
        case "full": displayMode = .full   // override the minimal default (e.g. for testing)
        default: break
        }
        if ProcessInfo.processInfo.environment["XENEON_SETTINGS"] != nil { showSettings = true }
    }

    func onAppear() {
        metrics.start()
        weather.start()
        todos.start()
        startTouch()
        if canControlBacklight {
            DispatchQueue.global(qos: .utility).async {
                if let b = Backlight.getBrightness() {
                    DispatchQueue.main.async { self.brightness = b; self.preDimBrightness = b }
                }
            }
        }
    }

    func startTouch() {
        touchOn = true
        attemptAcquire()
    }

    /// Try to open the digitizer; if it's held (e.g. by the xeneon-touch CLI) or
    /// not yet ready, keep retrying so touch comes alive once it's free.
    private func attemptAcquire() {
        guard touchOn else { return }
        if touch.start() {
            retryTimer?.invalidate(); retryTimer = nil
        } else if retryTimer == nil {
            let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.attemptAcquire() }
            }
            RunLoop.main.add(t, forMode: .common)
            retryTimer = t
        }
    }

    func stopTouch() {
        touchOn = false
        edgeDetected = false
        retryTimer?.invalidate(); retryTimer = nil
        touch.stop()
    }

    func toggleTouch() { touchOn ? stopTouch() : startTouch() }
}
