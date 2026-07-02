import AppKit
import SwiftUI
import ApplicationServices
import XeneonTouchDriver

/// A non-activating kiosk panel. Being an `NSPanel` with `.nonactivatingPanel` lets
/// a tap operate the Edge UI *without* making Xeneon Toolbox the active app — so a
/// glance at the panel while you're coding on the main display doesn't steal focus.
/// Paired with `becomesKeyOnlyIfNeeded`, only a control that genuinely needs the
/// keyboard (a text field) pulls focus, at which point `becomeKey` brings the app
/// forward so typing actually lands.
final class KeyableWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // becomesKeyOnlyIfNeeded means this only fires when a text field is tapped, so
    // activating here is exactly "the user wants to type" — not every stray tap.
    override func becomeKey() {
        super.becomeKey()
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
    }


    // A touchscreen deck has no keyboard chrome; if a keystroke reaches the window
    // unhandled (no text field or game focused), swallow it instead of letting
    // macOS sound the system alert beep. Menu shortcuts (⌘C etc.) use a separate
    // key-equivalent path and are unaffected.
    override func keyDown(with event: NSEvent) { /* swallow — no beep */ }
}

/// Lets a tap act immediately even when the window isn't focused, so injected
/// touches don't get "eaten" as a mere focus click (the refocus-with-mouse bug).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // NSHostingView returns true here, which made EVERY tap key the panel (and
    // KeyableWindow.becomeKey then activated the app — stealing focus from
    // whatever you were typing in on another screen). Buttons/tiles/gestures all
    // work without key status; SwiftUI text fields explicitly request key when
    // focused, which still lands in becomeKey and activates just-in-time.
    override var needsPanelToBecomeKey: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: KeyableWindow?
    private let model = ToolboxModel()
    private var noNapToken: NSObjectProtocol?
    private var devMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.install()
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        AppLog.info("lifecycle", "launched v\(ver) pid=\(ProcessInfo.processInfo.processIdentifier)")
        installMainMenu()

        // Touch injection needs Accessibility; prompt for it on launch so a new
        // (re-signed) build can be granted instead of silently failing.
        let axPrompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(axPrompt)
        touchDiag("launch: AXIsProcessTrusted=\(AXIsProcessTrusted()) bundleID=\(Bundle.main.bundleIdentifier ?? "nil")")

        // The touch driver reads the digitizer on the main run loop. When the app
        // isn't frontmost (you're working on another screen), App Nap would
        // throttle that loop and touch would freeze until you click back in.
        // Holding a user-initiated, latency-critical activity disables App Nap so
        // touch keeps working continuously.
        noNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Xeneon Edge touch input runs continuously, including while another app is focused")

        // Headless high-res export: render the UI off-screen at NxN scale (the UI
        // is vector, so this is far crisper than capturing the 2560x720 panel).
        // XENEON_RENDER="route@scale@warmupSeconds@/abs/out.png"
        if let spec = ProcessInfo.processInfo.environment["XENEON_RENDER"] {
            renderOffscreenThenExit(spec)
            return
        }

        devMode = ProcessInfo.processInfo.environment["XENEON_NO_FULLSCREEN"] != nil

        // Create the window titled (not borderless) so we can never end up with an
        // uncloseable cover. placeWindow() then decides, based on whether the Edge
        // is actually connected, whether to pin it to the panel as a kiosk or leave
        // it a normal movable/closable window.
        let initialFrame = (edgeScreen() ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 2560, height: 720)
        // .nonactivatingPanel must be present at creation — the window server bakes
        // the activation behavior into the window; adding the flag to styleMask
        // later does not stop clicks from activating the app.
        let win = KeyableWindow(contentRect: initialFrame,
                                styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                            .fullSizeContentView, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        win.title = "Xeneon Toolbox"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = false
        win.acceptsMouseMovedEvents = true
        win.contentView = FirstMouseHostingView(rootView: RootView(model: model, metrics: model.metrics))
        self.window = win

        placeWindow()
        NSApp.activate(ignoringOtherApps: true)
        fputs("WINDOW_ID=\(win.windowNumber)\n", stderr)

        if ProcessInfo.processInfo.environment["XENEON_WINDIAG"] != nil {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak win] _ in
                Task { @MainActor in
                    guard let win else { return }
                    fputs("DIAG vis=\(win.isVisible) key=\(win.isKeyWindow) active=\(NSApp.isActive) hidesOnDeactivate=\(win.hidesOnDeactivate) level=\(win.level.rawValue) responder=\(type(of: win.firstResponder as Any))\n", stderr)
                }
            }
        }

        // Displays can be added, removed, or rearranged at runtime, and on
        // sleep/wake macOS may move the window to another screen. Re-place the
        // window whenever that happens so the kiosk follows the Edge back and is
        // never stranded, untitled, on the main monitor.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Closing OUR window (the titled no-Edge mode has a close button) quits the
        // app — the panel-safe replacement for terminate-after-last-window-closed.
        NotificationCenter.default.addObserver(
            self, selector: #selector(mainWindowClosed),
            name: NSWindow.willCloseNotification, object: win)

        model.onAppear()

        // Dev hooks: exercise the restore→relaunch flow / the crash reporter.
        if ProcessInfo.processInfo.environment["XENEON_TEST_RELAUNCH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ConfigBackup.relaunch() }
        }
        if ProcessInfo.processInfo.environment["XENEON_TEST_CRASH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let empty: [Int] = []
                _ = empty[1]   // deliberate crash to test the reporter
            }
        }
    }

    // MUST be false: the kiosk is an NSPanel, and panels don't count as windows in
    // AppKit's "last window closed" bookkeeping. With true, any transient real
    // window closing (e.g. the input-method window a keystroke in a text field
    // spawns) reads as "last window closed" and silently terminates the app.
    // Quitting when OUR window closes is handled by the willClose observer below.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Re-seize the digitizer whenever the app regains focus, so tapping back into
    // it from another screen re-engages touch immediately.
    func applicationDidBecomeActive(_ notification: Notification) {
        model.reacquireTouch()
        // If the kiosk drifted off the Edge while we were away (e.g. a display
        // reshuffle that didn't fire a parameters change), pull it back.
        if !devMode, let edge = edgeScreen(), window?.screen != edge {
            placeWindow()
        }
    }

    /// Positions the main window. With the Edge connected it becomes a borderless
    /// kiosk covering the panel, above the menu bar so Esc/⌘ gestures can't exit
    /// (and so they reach the game). Without the Edge it stays a normal, movable,
    /// closable window on the main display — never an untitled cover with no way to
    /// move or quit it.
    private func placeWindow() {
        guard let win = window else { return }

        if devMode {
            stopYieldWatch()
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel]
            win.becomesKeyOnlyIfNeeded = false
            win.isFloatingPanel = false
            win.level = .normal
            win.makeKeyAndOrderFront(nil)
            return
        }

        if let edge = edgeScreen() {
            // Non-activating kiosk: a tap drives the panel without making us the
            // active app, so it never yanks focus off whatever you're doing on the
            // main display. becomesKeyOnlyIfNeeded means only a text field pulls
            // focus (see KeyableWindow.becomeKey); plain buttons/tiles never do.
            win.styleMask = [.borderless, .nonactivatingPanel]
            win.becomesKeyOnlyIfNeeded = true
            win.isFloatingPanel = true
            win.hidesOnDeactivate = false   // stay lit on the Edge while another app is focused
            // No .stationary: the window participates in Mission Control, so the
            // Edge screen's windows can be seen and switched like any other.
            win.collectionBehavior = [.canJoinAllSpaces]
            win.level = yielding ? .normal : Self.kioskLevel
            win.setFrame(edge.frame, display: true)
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
            // Show without stealing activation — but never jump above a window the
            // user is actively using on the Edge.
            if !behindActiveApp { win.orderFrontRegardless() }
            startYieldWatch()
        } else {
            stopYieldWatch()
            // No Edge connected: restore a normal titled window centered on the main
            // display, with a visible title and a close button, so it can always be
            // moved and quit. It re-pins to the Edge automatically once it appears.
            NSApp.presentationOptions = []
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel]
            win.becomesKeyOnlyIfNeeded = false
            win.isFloatingPanel = false
            win.collectionBehavior = [.managed]
            win.level = .normal
            win.titleVisibility = .visible
            win.title = "Xeneon Toolbox — connect the Xeneon Edge"
            let size = NSSize(width: 1280, height: 360)
            let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
            win.setFrame(NSRect(origin: origin, size: size), display: true)
            win.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        placeWindow()
    }

    @objc private func mainWindowClosed(_ note: Notification) {
        guard !quitting else { return }
        NSApp.terminate(nil)
    }

    // MARK: - Kiosk auto-yield
    //
    // The kiosk normally sits above the menu bar so the Edge is a clean panel. But
    // pinned there it buries any window you drag onto the Edge screen and makes
    // switching apps on it impossible. So we watch for another app's window on the
    // Edge: when one appears, the kiosk drops to normal level (that window can sit
    // above it, Mission Control can arrange it); when the screen is ours again, it
    // returns to kiosk level. Tapping a visible part of the yielded kiosk raises
    // it (see KeyableWindow.sendEvent) without stealing focus.

    static let kioskLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    private var yielding = false            // a window shares the Edge → normal level, pinned behind
    private var behindActiveApp = false     // mirror of yielding, read by placeWindow
    private var hiddenForFullscreen = false // a fullscreen app owns the Edge → panel ordered out
    private var yieldTimer: Timer?

    private func startYieldWatch() {
        guard yieldTimer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateYield() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        yieldTimer = t
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Space switches re-insert a canJoinAllSpaces window at the front of its
        // level — re-pin immediately, not a second later.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        updateYield()
    }

    private func stopYieldWatch() {
        yieldTimer?.invalidate(); yieldTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(
            self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(
            self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        yielding = false
        behindActiveApp = false
        hiddenForFullscreen = false
    }

    @objc private func activeAppChanged(_ note: Notification) {
        Task { @MainActor in self.updateYield() }
    }

    private func updateYield() {
        guard let win = window, !devMode, edgeScreen() != nil,
              let edge = Self.edgeDisplayBoundsCG() else { return }

        // Desktop metaphor: a window placed on the Edge stays VISIBLE above the
        // panel — even while its app isn't frontmost — so a video or reference
        // window keeps showing while you work elsewhere. While any such window
        // exists the panel is the screen's backdrop (normal level, kept at the
        // BACK); close or move the window away and the full-bleed above-menu-bar
        // kiosk returns automatically. The back-pinning must be re-asserted on
        // every pass: Space switches and window switches re-insert a
        // canJoinAllSpaces window at the front of its level, which is exactly the
        // "panel floats over the app after I switch windows" bug.
        let state = Self.edgeOccupancy(edge)

        // An app FULLSCREEN on the Edge (its own Space) owns the whole screen:
        // there's no window stack to sit behind there — a canJoinAllSpaces panel
        // would float on top of it — so hide the panel entirely until the Edge
        // leaves that Space.
        let hide = state == .fullscreen
        if hide != hiddenForFullscreen {
            hiddenForFullscreen = hide
            AppLog.info("yield", hide ? "fullscreen app owns the Edge — panel hidden" : "fullscreen gone — panel back")
            if hide { win.orderOut(nil) } else { win.order(.below, relativeTo: 0) }
        }
        guard !hide else { return }

        let shouldYield = state == .shared
        if ProcessInfo.processInfo.environment["XENEON_WINDIAG"] != nil {
            fputs("DIAG yield state=\(state) yielding=\(yielding)\n", stderr)
        }
        if shouldYield == yielding {
            if yielding { win.order(.below, relativeTo: 0) }   // stay pinned behind
            return
        }
        yielding = shouldYield
        behindActiveApp = shouldYield
        AppLog.info("yield", shouldYield ? "window on Edge — panel drops behind" : "Edge clear — kiosk restored")
        if shouldYield {
            win.level = .normal
            win.order(.below, relativeTo: 0)   // sit behind the Edge's windows
        } else {
            win.level = Self.kioskLevel
            win.orderFrontRegardless()
        }
    }

    /// The Edge display's bounds in CG (top-left origin) global coordinates —
    /// the space CGWindowList reports window bounds in.
    private static func edgeDisplayBoundsCG() -> CGRect? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        for i in 0..<Int(n) {
            let b = CGDisplayBounds(ids[i])
            if abs(b.width - 2560) < 2, abs(b.height - 720) < 2 { return b }
        }
        return nil
    }

    enum EdgeOccupancy { case free, shared, fullscreen }

    /// What other apps are doing on the Edge: nothing, sharing it with ordinary
    /// windows, or owning it outright with a (near-)fullscreen window. Layer 0
    /// filters the menu bar, Dock, and system chrome.
    private static func edgeOccupancy(_ edge: CGRect) -> EdgeOccupancy {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return .free
        }
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        let edgeArea = edge.width * edge.height
        var occupancy = EdgeOccupancy.free
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int, pid != myPID,
                  let bd = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0,
                           width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
            guard r.width > 1, r.height > 1 else { continue }   // ghost/ornament windows
            let inter = r.intersection(edge)
            guard !inter.isNull else { continue }
            let area = inter.width * inter.height
            if area > edgeArea * 0.95 { return .fullscreen }   // owns the whole screen
            if area > 20_000 { occupancy = .shared }           // ignore slivers
        }
        return occupancy
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.info("lifecycle", "clean exit")
        CrashReporter.markCleanExit()
        model.restoreBacklightOnQuit()   // don't leave the Edge dark if we quit while asleep
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true   // so the window closing during teardown doesn't re-enter terminate
        return .terminateNow
    }
    private var quitting = false

    private func renderOffscreenThenExit(_ spec: String) {
        let parts = spec.components(separatedBy: "@")
        guard parts.count == 4, let scale = Double(parts[1]), let warmup = Double(parts[2]) else {
            fputs("XENEON_RENDER bad spec; expected route@scale@warmup@/path\n", stderr); NSApp.terminate(nil); return
        }
        let route = parts[0], outPath = parts[3]
        if let r = AppRoute(rawValue: route == "assistant" ? "chat" : route) { model.route = r }
        if route == "minimal" { model.displayMode = .minimal }
        else if route == "sleep" { model.displayMode = .sleep }
        else { model.displayMode = .full }   // render the actual page, not the minimal overlay
        model.exportMode = true   // static add bars / non-scroll lists for off-screen render
        if route == "assistant" {
            model.agent.turns = [
                .init(role: "user", text: "Compare the RTX 4090, RTX 4080 Super, and RX 7900 XTX"),
                .init(role: "card", text: "", card: .table(title: "GPU Comparison",
                    headers: ["GPU", "VRAM", "TDP", "MSRP"],
                    rows: [["RTX 4090", "24 GB", "450 W", "$1599"],
                           ["RTX 4080 Super", "16 GB", "320 W", "$999"],
                           ["RX 7900 XTX", "24 GB", "355 W", "$949"]])),
                .init(role: "assistant", text: "The **4090** leads on raw performance; the **7900 XTX** matches its VRAM for less. The **4080 Super** is the efficiency pick."),
            ]
        }
        model.touchOn = true; model.edgeDetected = true   // show Touch "Active" in demo renders
        model.metrics.start()
        model.weather.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + warmup) { [self] in
            let content = RootView(model: model, metrics: model.metrics)
                .frame(width: 2560, height: 720)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = CGFloat(scale)
            guard let cg = renderer.cgImage else { fputs("render failed\n", stderr); NSApp.terminate(nil); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outPath))
                fputs("RENDERED \(cg.width)x\(cg.height) -> \(outPath)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

    /// Without a main menu, standard editing shortcuts (⌘A select-all, ⌘C/⌘V,
    /// undo) never reach the focused text field. This wires them up.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Xeneon Toolbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = main
    }

    private func edgeScreen() -> NSScreen? {
        NSScreen.screens.first {
            abs($0.frame.width - 2560) < 2 && abs($0.frame.height - 720) < 2
        }
    }
}
