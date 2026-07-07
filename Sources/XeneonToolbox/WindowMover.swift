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

        if let running {
            running.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                relocateEdgeWindows(pid: running.processIdentifier, to: main)
            }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            guard let app else { return }
            // A freshly-launched app draws its window a beat later; nudge it then.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                relocateEdgeWindows(pid: app.processIdentifier, to: main)
            }
        }
    }

    /// Open (or focus) the app at `appPath` and place its windows on `display`.
    static func open(appPath: String, on display: Display) {
        let url = URL(fileURLWithPath: appPath)
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let running = bundleID.flatMap { id in NSRunningApplication.runningApplications(withBundleIdentifier: id).first }

        AppLog.info("deck", "open '\(appPath)' on \(display.name)\(running != nil ? " (running — moving)" : "")")

        if let running {
            running.activate()
            moveWindows(pid: running.processIdentifier, to: display)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            guard let app else { return }
            // Give the app a moment to create its window, then place it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                moveWindows(pid: app.processIdentifier, to: display)
            }
        }
    }

    /// Move only the windows whose centre currently sits on the Edge onto
    /// `display`, keeping each window's size (clamped to fit). Windows already on
    /// another display are untouched — so a running app the user focuses from the
    /// deck stays put unless it was actually covering the kiosk.
    static func relocateEdgeWindows(pid: pid_t, to display: Display) {
        guard let edge = displays().first(where: { $0.isEdge }) else { return }
        let axApp = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return }

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
        }
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
