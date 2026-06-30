import SwiftUI
import XeneonTouchDriver
import ToolboxKit

enum DisplayMode { case full, minimal, sleep }

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard, clock, tasks, games, web, chat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .clock: return "Clock"
        case .tasks: return "Tasks"
        case .games: return "Games"
        case .web: return "Web"
        case .chat: return "Assistant"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .clock: return "clock.fill"
        case .tasks: return "checklist"
        case .games: return "gamecontroller.fill"
        case .web: return "globe"
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
        case .web: return Theme.disk
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
    let webApps = WebAppStore()
    let media = MediaController()
    let dashboardLayout = DashboardLayout()
    let canControlBacklight = Backlight.isAvailable
    @Published var brightness: Int = 90          // Edge backlight 0–100 (DDC)
    private var preDimBrightness = 90             // restored when waking from sleep
    lazy var agent = AgentController(config: ChatConfig.loadSaved() ?? ChatConfig.presets[0].config, app: self)
    lazy var remote = RemoteServer(model: self)
    lazy var web = WebController()   // persists the Web tab's page/history across tab switches
    lazy var updater = UpdateChecker()
    @Published var remoteEnabled = (UserDefaults.standard.object(forKey: "remote.enabled") as? Bool) ?? true
    @Published var route: AppRoute = .dashboard
    @Published var displayMode: DisplayMode = .minimal   // ambient default; tap to wake to full
    @Published var fullscreen = false                    // hide the nav rail; page fills the panel
    @Published var pendingWebURL: String?                // a URL the Web tab should open (agent/remote)
    @Published var showNowPlaying = (UserDefaults.standard.object(forKey: "ui.showNowPlaying") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showNowPlaying, forKey: "ui.showNowPlaying") }
    }
    @Published var showSettings = false
    var exportMode = false   // static input bar etc. for off-screen mockup renders
    @Published var touchOn = false
    @Published var edgeDetected = false
    @Published var gamePref = "rhythm"

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
        if mode != .full { fullscreen = false }   // don't wake straight back into immersive mode
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
    private let cursor = CursorController()
    private var retryTimer: Timer?

    private func makeTouch() -> TouchService {
        let t = TouchService(config: TouchServiceConfig(flipX: flipX, flipY: flipY, swapXY: swapXY, preferSeize: true))
        t.onPresenceChanged = { [weak self] present in Task { @MainActor in self?.edgeDetected = present } }
        t.onSystemGesture = { [weak self] g in Task { @MainActor in self?.handleSystemGesture(g) } }
        return t
    }

    /// Whole-screen edge swipes recognized by the driver: up from the bottom exits
    /// fullscreen; down from the top drops to the minimal/idle screen.
    private func handleSystemGesture(_ gesture: SystemGesture) {
        switch gesture {
        case .swipeUpFromBottom:
            if fullscreen { withAnimation(.easeInOut(duration: 0.3)) { fullscreen = false } }
        case .swipeDownFromTop:
            if displayMode == .full { setDisplay(.minimal) }
        }
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
        if ProcessInfo.processInfo.environment["XENEON_FULLSCREEN"] != nil { fullscreen = true }
        if let u = ProcessInfo.processInfo.environment["XENEON_OPEN_URL"] { route = .web; pendingWebURL = u }
    }

    func onAppear() {
        metrics.start()
        weather.start()
        todos.start()
        media.start()
        startTouch()
        if remoteEnabled { remote.start() }
        if ProcessInfo.processInfo.environment["XENEON_UPDATE_DEMO"] != nil { updater.demo() } else { updater.start() }
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
        cursor.start()   // hide the pointer while touching; shows again on real mouse use
        attemptAcquire()
    }

    /// Open + seize the digitizer once. If the manager can't open yet (e.g. the
    /// `xeneon-touch` CLI holds it), retry every few seconds until it can. Once
    /// open, the IOHIDManager matches the panel on its own and re-matches if it's
    /// reconnected — no need to keep tearing it down (that thrash kept touch stuck
    /// "searching" and let macOS grab the panel as a trackpad in the gaps).
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

    /// Re-seize when the app regains focus — but only if we're not already driving
    /// the panel, so a working session is never interrupted. This restores touch
    /// after macOS has reclaimed the digitizer (as a trackpad) while backgrounded.
    func reacquireTouch() {
        guard touchOn, !edgeDetected else { return }
        touch.stop()
        attemptAcquire()
    }

    func stopTouch() {
        touchOn = false
        edgeDetected = false
        retryTimer?.invalidate(); retryTimer = nil
        touch.stop()
        cursor.stop()
    }

    func toggleTouch() { touchOn ? stopTouch() : startTouch() }

    func toggleFullscreen() { fullscreen.toggle() }

    /// Open a web page in the Web tab — used by the assistant and the remote.
    /// Wakes the panel and switches to the tab; the BrowserView picks up the URL.
    func openWeb(_ urlString: String) {
        if displayMode != .full { setDisplay(.full) }
        route = .web
        pendingWebURL = urlString
    }

    func setRemote(_ enabled: Bool) {
        remoteEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "remote.enabled")
        if enabled { remote.start() } else { remote.stop() }
    }
}
