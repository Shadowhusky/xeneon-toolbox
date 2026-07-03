import SwiftUI
import XeneonTouchDriver
import ToolboxKit

enum DisplayMode { case full, minimal, sleep }

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard, deck, clock, tasks, games, web, chat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .deck: return "Deck"
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
        case .deck: return "square.grid.3x3.fill"
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
        case .deck: return Theme.battery
        case .clock: return Theme.time
        case .tasks: return Theme.netUp
        case .games: return Theme.gpu
        case .web: return Theme.disk
        case .chat: return Theme.memory
        }
    }

    /// Routes shown as nav tabs and reachable by side-swipe. The browser (`.web`) is
    /// no longer its own tab — it's opened by tapping a website tile on the Deck — so
    /// it's excluded here, which also gives the remaining tabs more room.
    static var tabs: [AppRoute] { allCases.filter { $0 != .web } }
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
    let deck = DeckStore()
    let calendar = CalendarService()
    let systemToggles = SystemToggles()
    let canControlBacklight = Backlight.isAvailable
    @Published var brightness: Int = 90          // Edge backlight 0–100 (DDC)
    private var preDimBrightness = 90             // restored when waking from sleep
    lazy var agent = AgentController(config: ChatConfig.loadSaved() ?? ChatConfig.presets[0].config, app: self)
    lazy var remote = RemoteServer(model: self)
    lazy var web = WebController()   // persists the Web tab's page/history across tab switches
    lazy var updater = UpdateChecker()
    @Published var remoteEnabled = (AppDefaults.shared.object(forKey: "remote.enabled") as? Bool) ?? true
    /// How the page change should animate: swipes slide directionally (the page
    /// follows the finger); tab taps and programmatic jumps cross-fade with a
    /// gentle settle — a slide there reads as a phantom swipe.
    enum PageTransition { case slideForward, slideBackward, fade }
    @Published var route: AppRoute = .dashboard {
        didSet {
            guard oldValue != route else { return }
            if let d = swipeDirection {
                pageTransition = d > 0 ? .slideForward : .slideBackward
                swipeDirection = nil
            } else {
                pageTransition = .fade
            }
        }
    }
    private(set) var pageTransition: PageTransition = .fade   // read in the same render pass
    private var swipeDirection: Int?
    @Published var displayMode: DisplayMode = .minimal   // ambient default; tap to wake to full
    @Published var fullscreen = false {                  // hide the nav rail; page fills the panel
        didSet {
            if fullscreen, !oldValue, !fsTutorialSeen { showFsTutorial = true }
        }
    }
    @Published var showFsTutorial = false                // first-run fullscreen gesture coach marks
    private var fsTutorialSeen = AppDefaults.shared.bool(forKey: "tutorial.fullscreen.seen")

    func dismissFsTutorial() {
        showFsTutorial = false
        fsTutorialSeen = true
        AppDefaults.shared.set(true, forKey: "tutorial.fullscreen.seen")
    }
    @Published var pullFrac: Double?                     // 0…1 minimal-screen bottom while dragging it in/out from an edge
    @Published var controlExt: Double = 0                // 0…1 how far the control centre is pulled down
    @Published var pendingWebURL: String?                // a URL the Web tab should open (agent/remote)
    @Published var showNowPlaying = (AppDefaults.shared.object(forKey: "ui.showNowPlaying") as? Bool) ?? true {
        didSet { AppDefaults.shared.set(showNowPlaying, forKey: "ui.showNowPlaying") }
    }
    @Published var showSettings = false
    @Published var crashPrompt: CrashReport?   // last session's crash — offer to report it
    var exportMode = false   // static input bar etc. for off-screen mockup renders

    func sendCrashReport() {
        guard let report = crashPrompt else { return }
        if let url = CrashReporter.githubIssueURL(for: report) { NSWorkspace.shared.open(url) }
        CrashReporter.markHandled(report)
        crashPrompt = nil
    }

    func dismissCrashReport() {
        guard let report = crashPrompt else { return }
        CrashReporter.markHandled(report)
        crashPrompt = nil
    }
    @Published var touchOn = false
    @Published var edgeDetected = false
    @Published var gamePref = "rhythm"

    // Touch calibration — flips persist and rebuild the driver when changed.
    @Published var flipX = AppDefaults.shared.bool(forKey: "touch.flipX") { didSet { applyCalibration() } }
    @Published var flipY = AppDefaults.shared.bool(forKey: "touch.flipY") { didSet { applyCalibration() } }
    @Published var swapXY = AppDefaults.shared.bool(forKey: "touch.swapXY") { didSet { applyCalibration() } }

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

    /// Run a deck tile: launch an app, open a URL in the default browser, control
    /// media, or fire an in-app system action.
    func runDeck(_ action: DeckAction) {
        AppLog.info("deck", "run \(action.kind.rawValue): \(action.label)")
        switch action.kind {
        case .app:
            NSWorkspace.shared.open(URL(fileURLWithPath: action.target))
        case .url:
            openWeb(action.target)   // open in the in-app browser (merged with the old saved-sites)
        case .media:
            switch DeckMediaAction(rawValue: action.target) {
            case .playPause: media.togglePlayPause()
            case .next: media.next()
            case .previous: media.previous()
            case nil: break
            }
        case .system:
            runSystemAction(DeckSystemAction(rawValue: action.target))
        case .command:
            shell("/bin/sh", ["-c", action.target])
        case .webhook:
            var s = action.target
            if !s.contains("://") { s = "https://" + s }
            guard let u = URL(string: s) else { return }
            var req = URLRequest(url: u)
            req.httpMethod = action.httpMethod ?? "GET"
            if let body = action.httpBody, !body.isEmpty {
                req.httpBody = body.data(using: .utf8)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            URLSession.shared.dataTask(with: req).resume()
        case .keystroke:
            guard let code = action.keyCode else { return }
            KeyCombo.post(keyCode: CGKeyCode(code), modifiers: action.modifiers ?? 0)
        case .multi:
            // Run the sequence with a beat between steps so each lands (apps
            // need a moment to activate before hotkeys/media hit them).
            let steps = (action.steps ?? []).filter { $0.kind != .multi }
            Task { @MainActor in
                for step in steps {
                    runDeck(step)
                    try? await Task.sleep(nanoseconds: 350_000_000)
                }
            }
        }
    }

    private func runSystemAction(_ action: DeckSystemAction?) {
        switch action {
        case .minimal: setDisplay(.minimal)
        case .sleepDisplay: shell("/usr/bin/pmset", ["displaysleepnow"])
        case .missionControl: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .launchpad: shell("/usr/bin/open", ["-a", "Launchpad"])
        case .screenshot: shell("/usr/sbin/screencapture", ["-i", "-c"])   // interactive → clipboard
        case .lockScreen:
            shell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"])
        case nil: break
        }
    }

    private func shell(_ launchPath: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try? p.run()
    }

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
    private var healthTimer: Timer?
    private var wakeObservers: [NSObjectProtocol] = []

    /// Locking the Mac silently invalidates the HID seize: after unlock the
    /// manager is open but dead and touch sits in "Searching" forever. The app
    /// never activates (by design), so the old did-become-active reacquire can't
    /// save it — listen for unlock/wake directly, and back it with a watchdog
    /// that reacquires whenever touch stays wanted-but-missing.
    private func startTouchRecovery() {
        guard wakeObservers.isEmpty else { return }
        let unlockName = Notification.Name("com.apple.screenIsUnlocked")
        wakeObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: unlockName, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                AppLog.info("touch", "screen unlocked — reacquiring digitizer")
                self?.reacquireSoon()
            }
        })
        wakeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                AppLog.info("touch", "displays woke — reacquiring digitizer")
                self?.reacquireSoon()
            }
        })
        let t = Timer(timeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.touchOn, !self.edgeDetected else { return }
                AppLog.info("touch", "watchdog: still searching — reacquiring digitizer")
                self.reacquireTouch()
            }
        }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        healthTimer = t
    }

    /// Give USB a beat to settle after wake before reopening the device.
    private func reacquireSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.reacquireTouch()
        }
    }

    private func makeTouch() -> TouchService {
        let t = TouchService(config: TouchServiceConfig(flipX: flipX, flipY: flipY, swapXY: swapXY, preferSeize: true))
        t.onPresenceChanged = { [weak self] present in Task { @MainActor in
            if self?.edgeDetected != present { AppLog.info("touch", present ? "digitizer connected" : "digitizer lost") }
            self?.edgeDetected = present
        } }
        t.onShadePull = { [weak self] frac, phase in Task { @MainActor in self?.handleShadePull(frac, phase) } }
        t.onControlPull = { [weak self] frac, phase in Task { @MainActor in self?.handleControlPull(frac, phase) } }
        t.onBottomPull = { [weak self] frac, phase in Task { @MainActor in self?.handleBottomPull(frac, phase) } }
        t.onSwipeApp = { [weak self] next in Task { @MainActor in self?.handleSwipeApp(next) } }
        t.sideSwipeEnabled = true   // side swipes work in the full UI too (auto-enter fullscreen)
        return t
    }

    /// Swipe in from a side edge to flip to the previous/next app. From the
    /// normal full UI this also enters fullscreen — the swipe reads as "give me
    /// the immersive app view", matching the fullscreen gesture language.
    private func handleSwipeApp(_ next: Bool) {
        guard displayMode == .full else { return }
        let all = AppRoute.tabs
        guard let i = all.firstIndex(of: route) else { return }
        let j = next ? (i + 1) % all.count : (i - 1 + all.count) % all.count
        swipeDirection = next ? 1 : -1   // page follows the finger, even on wrap-around
        withAnimation(.easeInOut(duration: 0.28)) {
            if !fullscreen { fullscreen = true }
            route = all[j]
        }
    }

    private var dismissing = false
    private var closingControl = false
    private func controlExtent(_ frac: Double) -> Double { min(1, frac / 0.68) }

    /// Pull down from the top edge (in full) to drag the minimal screen into view —
    /// its bottom tracks the finger. Release past the threshold drops to it.
    private func handleShadePull(_ fraction: Double, _ phase: EdgePhase) {
        guard displayMode == .full, !dismissing else { return }
        switch phase {
        case .began, .changed: pullFrac = fraction
        case .ended: commit(to: fraction > 0.32 ? .minimal : .full, settle: fraction > 0.32 ? 1 : 0)
        }
    }

    /// Pull down from the top-right edge to bring the control centre down; release
    /// past the threshold latches it open, otherwise it retracts.
    private func handleControlPull(_ fraction: Double, _ phase: EdgePhase) {
        guard displayMode != .sleep else { return }
        switch phase {
        case .began, .changed: controlExt = controlExtent(fraction)
        case .ended: withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { controlExt = fraction > 0.3 ? 1 : 0 }
        }
    }

    func closeControlCenter() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { controlExt = 0 }
    }

    /// Pull up from the bottom edge. Closes the control centre if it's open; else in
    /// minimal it drags the minimal screen up to the full UI; in fullscreen it exits.
    private func handleBottomPull(_ fraction: Double, _ phase: EdgePhase) {
        switch phase {
        case .began:
            if controlExt > 0.5 {
                closingControl = true
                controlExt = controlExtent(fraction)
            } else if displayMode == .minimal {
                dismissing = true
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { setDisplay(.full) }
                pullFrac = fraction
            }
        case .changed:
            if closingControl { controlExt = controlExtent(fraction) }
            else if dismissing { pullFrac = fraction }
        case .ended:
            if closingControl {
                closingControl = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { controlExt = fraction < 0.45 ? 0 : 1 }
            } else if dismissing {
                dismissing = false
                commit(to: fraction < 0.6 ? .full : .minimal, settle: fraction < 0.6 ? 0 : 1)
            } else if fullscreen, fraction < 0.62 {
                withAnimation(.easeInOut(duration: 0.3)) { fullscreen = false }
            }
        }
    }

    /// Settle the pull to its end, then switch display mode with animation off and
    /// clear the overlay in the same step — the destination is already shown when
    /// the overlay goes, so neither screen flashes.
    private func commit(to mode: DisplayMode, settle: Double) {
        withAnimation(.easeOut(duration: 0.16)) { pullFrac = settle } completion: {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                self.setDisplay(mode)
                self.pullFrac = nil
            }
        }
    }

    private func applyCalibration() {
        AppDefaults.shared.set(flipX, forKey: "touch.flipX")
        AppDefaults.shared.set(flipY, forKey: "touch.flipY")
        AppDefaults.shared.set(swapXY, forKey: "touch.swapXY")
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
        if let s = ProcessInfo.processInfo.environment["XENEON_SHADE"], let v = Double(s) { pullFrac = v }
        if ProcessInfo.processInfo.environment["XENEON_CONTROL"] != nil { controlExt = 1 }
        if ProcessInfo.processInfo.environment["XENEON_TUTORIAL"] != nil {
            displayMode = .full; fullscreen = true; showFsTutorial = true
        }
        migrateWebAppsToDeck()
    }

    /// One-time: fold the old "Saved sites" bookmarks into the Deck as website tiles,
    /// so websites live in a single place. Runs once; deduped by canonical URL.
    private func migrateWebAppsToDeck() {
        let flag = "deck.webAppsMigrated.v1"
        guard !AppDefaults.shared.bool(forKey: flag) else { return }
        for app in webApps.apps {
            let key = WebAppStore.canonicalKey(app.urlString)
            if !deck.actions.contains(where: { $0.kind == .url && WebAppStore.canonicalKey($0.target) == key }) {
                deck.add(.url(app.urlString, label: app.title))
            }
        }
        AppDefaults.shared.set(true, forKey: flag)
    }

    func onAppear() {
        crashPrompt = CrashReporter.pendingReport()
        metrics.start()
        weather.start()
        todos.start()
        calendar.start()
        startTouchRecovery()
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
            AppLog.info("touch", "driver started")
            retryTimer?.invalidate(); retryTimer = nil
        } else if retryTimer == nil {
            AppLog.error("touch", "driver couldn't open the digitizer — retrying every 3s")
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

    /// While a grid is in edit mode, the driver must treat ANY single-finger move
    /// as a mouse drag — its default classification turns vertical/diagonal moves
    /// into scroll events with no press, which makes 2-D drag-to-reorder
    /// impossible. Views enable this for exactly as long as they're editing.
    /// Mode changes also flush any held press so a missed touch-up can never
    /// leave the panel with a phantom button down (everything reads as dead).
    func setReorderDragging(_ on: Bool) {
        touch.dragAnywhereEnabled = on
        touch.flushPointer()
    }

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
        AppDefaults.shared.set(enabled, forKey: "remote.enabled")
        if enabled { remote.start() } else { remote.stop() }
    }
}
