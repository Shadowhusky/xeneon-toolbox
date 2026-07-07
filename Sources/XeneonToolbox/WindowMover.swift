import AppKit
import ApplicationServices

/// Opens an app on a chosen display, or — if it's already running — moves its
/// windows there. Window positioning uses the Accessibility API (the same grant
/// the touch driver already needs), which is the only way to place another app's
/// windows. Coordinates are top-left global (CGDisplayBounds / AX space).
@MainActor
enum WindowMover {
    struct Display: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let bounds: CGRect       // top-left global
        let isEdge: Bool
    }

    /// Connected displays with friendly names, in left-to-right order.
    static func displays() -> [Display] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        let screensByNumber: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { s in
                (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { ($0, s) }
            })
        return (0..<Int(count)).map { i -> Display in
            let did = ids[i]
            let b = CGDisplayBounds(did)
            let isEdge = abs(b.width - 2560) < 2 && abs(b.height - 720) < 2
            let name: String
            if isEdge {
                name = "Xeneon Edge"
            } else if let s = screensByNumber[did] {
                name = s.localizedName
            } else {
                name = CGDisplayIsBuiltin(did) != 0 ? "Built-in Display" : "Display \(i + 1)"
            }
            return Display(id: did, name: name, bounds: b, isEdge: isEdge)
        }.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    /// Is the app at `appPath` currently running?
    static func isRunning(appPath: String) -> Bool { running(appPath) != nil }

    private static func running(_ appPath: String) -> NSRunningApplication? {
        guard let bundleID = Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Quit the app (graceful terminate).
    static func quit(appPath: String) {
        if let app = running(appPath) {
            AppLog.info("deck", "quit '\(appPath)'")
            app.terminate()
        }
    }

    /// Launch or focus an app from the deck WITHOUT letting it cover the Edge
    /// kiosk: any window that lands on the Edge is nudged onto the main display.
    /// Windows the app already has elsewhere are left exactly where they are, so
    /// focusing a running app doesn't rearrange it. Use for a normal tile tap; the
    /// long-press picker's `open(on:)` is the explicit "put it here" path.
    static func openOffEdge(appPath: String) {
        let url = URL(fileURLWithPath: appPath)
        // Prefer the widest non-Edge display (the user's main monitor). If the
        // Edge is the only screen there's nowhere else to put it — just open.
        guard let main = displays().filter({ !$0.isEdge }).max(by: { $0.bounds.width < $1.bounds.width }) else {
            NSWorkspace.shared.open(url)
            return
        }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let running = bundleID.flatMap { id in NSRunningApplication.runningApplications(withBundleIdentifier: id).first }

        AppLog.info("deck", "open '\(appPath)' off-Edge → main '\(main.name)'\(running != nil ? " (running)" : "")")

        // Activation is what brings the app forward; then poll (windows only
        // become AX-listable ~0.5s after their Space activates) and nudge any
        // Edge-covering window to main until none remain.
        running?.activate()
        if let running {
            nudgeOffEdge(pid: running.processIdentifier, main: main)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            guard let app else { return }
            DispatchQueue.main.async { nudgeOffEdge(pid: app.processIdentifier, main: main) }
        }
    }

    /// Poll for the app's windows and move Edge-covering ones to `main`, retrying
    /// because the window list is empty until the app's Space is active (~0.5s)
    /// and slow apps draw later still. Stops once windows are visible and none
    /// sit on the Edge, or after ~2.5s.
    private static func nudgeOffEdge(pid: pid_t, main: Display, attempt: Int = 0) {
        let r = relocateEdgeWindows(pid: pid, to: main)
        if (r.saw && r.moved == 0) || attempt >= 9 { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            nudgeOffEdge(pid: pid, main: main, attempt: attempt + 1)
        }
    }

    /// Open (or focus) the app at `appPath` and place its windows on `display`.
    static func open(appPath: String, on display: Display) {
        let url = URL(fileURLWithPath: appPath)
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let running = bundleID.flatMap { id in NSRunningApplication.runningApplications(withBundleIdentifier: id).first }

        AppLog.info("deck", "open '\(appPath)' on \(display.name)\(running != nil ? " (running — moving)" : "")")

        running?.activate()
        let launch: (pid_t) -> Void = { pid in whenWindowsAppear(pid: pid) { moveWindows(pid: pid, to: display) } }
        if let running {
            launch(running.processIdentifier)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            guard let app else { return }
            DispatchQueue.main.async { launch(app.processIdentifier) }
        }
    }

    /// Invoke `action` once the app's windows are AX-listable (they aren't until
    /// the app's Space activates ~0.5s after launch/activation), retrying up to
    /// ~2.5s. Placement (move/resize) is reliable only once a window exists.
    private static func whenWindowsAppear(pid: pid_t, attempt: Int = 0, _ action: @escaping () -> Void) {
        let axApp = AXUIElementCreateApplication(pid)
        var wv: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &wv) == .success,
           let wins = wv as? [AXUIElement], !wins.isEmpty {
            action()
            return
        }
        guard attempt < 9 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            whenWindowsAppear(pid: pid, attempt: attempt + 1, action)
        }
    }

    /// Move only the windows whose centre currently sits on the Edge onto
    /// `display`, keeping each window's size (clamped to fit). Windows already on
    /// another display are untouched — so a running app the user focuses from the
    /// deck stays put unless it was actually covering the kiosk. Returns whether
    /// any windows were listable (the Space is active yet) and how many were
    /// moved, so a poller knows when to stop.
    @discardableResult
    static func relocateEdgeWindows(pid: pid_t, to display: Display) -> (saw: Bool, moved: Int) {
        guard let edge = displays().first(where: { $0.isEdge }) else { return (false, 0) }
        let axApp = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return (false, 0) }

        var moved = 0
        for window in windows {
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            if let sr = subrole as? String, sr != (kAXStandardWindowSubrole as String) { continue }

            var posValue: CFTypeRef?
            var pos = CGPoint.zero
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
                  let pv = posValue, CFGetTypeID(pv) == AXValueGetTypeID() else { continue }
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)

            var sizeValue: CFTypeRef?
            var size = CGSize(width: 800, height: 600)
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                AXValueGetValue(sv as! AXValue, .cgSize, &size)
            }

            // Only relocate windows actually overlapping the Edge.
            let centre = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
            guard edge.bounds.contains(centre) else { continue }

            let w = min(size.width, display.bounds.width)
            let h = min(size.height, display.bounds.height)
            if w != size.width || h != size.height {
                var newSize = CGSize(width: w, height: h)
                if let v = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
                }
            }
            var origin = CGPoint(x: display.bounds.midX - w / 2, y: display.bounds.midY - h / 2)
            if let v = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            moved += 1
        }
        return (!windows.isEmpty, moved)
    }

    /// Move an app's on-screen windows onto the target display, keeping their
    /// relative offset within the display so a window that was centred stays
    /// roughly centred.
    static func moveWindows(pid: pid_t, to display: Display) {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return }

        for window in windows {
            // Skip minimized / non-standard windows.
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            if let sr = subrole as? String, sr != (kAXStandardWindowSubrole as String) { continue }

            var sizeValue: CFTypeRef?
            var size = CGSize(width: 800, height: 600)
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                AXValueGetValue(sv as! AXValue, .cgSize, &size)
            }
            // Clamp the window to fit, then centre it on the target display.
            let w = min(size.width, display.bounds.width)
            let h = min(size.height, display.bounds.height)
            if w != size.width || h != size.height {
                var newSize = CGSize(width: w, height: h)
                if let v = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
                }
            }
            var origin = CGPoint(x: display.bounds.midX - w / 2,
                                 y: display.bounds.midY - h / 2)
            if let v = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }
}
