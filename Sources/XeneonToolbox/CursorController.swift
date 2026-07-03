import AppKit
import CoreGraphics
import XeneonTouchDriver

// Private CGS API: lets a BACKGROUND app hide/show the cursor. Without it,
// CGDisplayHideCursor is silently ignored unless the app is frontmost — and the
// kiosk deliberately stays in the background while you touch it (so it never
// steals focus).
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: UInt32, _ target: UInt32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// Hides the pointer while the user is touching the panel, and shows it again the
/// instant a real mouse or trackpad is used. The touch driver stamps every event
/// it injects with `kXeneonTouchEventTag` (via the event source's user data), so
/// anything arriving without that tag is a physical pointing device.
///
/// Detection uses a listen-only CGEvent tap: NSEvent monitors don't reliably see
/// pointer events while the app is inactive (which is always, by design), but a
/// HID-level tap sees everything. macOS also re-shows the cursor on its own when
/// app focus changes, so the hide is re-asserted about once a second while touch
/// events keep flowing (show/hide kept balanced — hides never accumulate).
@MainActor
final class CursorController {
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var hidden = false
    private var lastAssert: CFAbsoluteTime = 0
    private let enabled = ProcessInfo.processInfo.environment["XENEON_NOHIDECURSOR"] == nil

    /// Call before ANY other window-server interaction (first thing in main) —
    /// set later, the property doesn't take and background hides are ignored.
    static func allowBackgroundCursorControl() {
        let cid = CGSMainConnectionID()
        let rc = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        AppLog.info("cursor", "SetsCursorInBackground rc=\(rc)")
    }

    func start() {
        guard enabled, tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, info in
                let controller = Unmanaged<CursorController>.fromOpaque(info!).takeUnretainedValue()
                let tagged = event.getIntegerValueField(.eventSourceUserData) == kXeneonTouchEventTag
                // The tap is scheduled on the main run loop, so this is main-thread.
                MainActor.assumeIsolated {
                    if tagged {
                        controller.assertHidden()
                        if event.type == .leftMouseUp {
                            controller.parkNow()   // finger lifted — hide the arrow instantly
                        } else {
                            controller.scheduleParkAfterTouch()   // covers scroll/momentum tails
                        }
                    } else {
                        controller.show()
                        controller.cancelPark()   // never park the user's real pointer
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: info) else {
            AppLog.error("cursor", "couldn't create the event tap — cursor won't hide during touch")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        tapSource = nil
        show()
    }

    /// Hide, and keep hiding: focus changes re-show the cursor behind our back,
    /// so while touches keep arriving, re-assert about once a second (balancing
    /// the counter so a later show() fully restores the cursor).
    private func assertHidden() {
        let now = CFAbsoluteTimeGetCurrent()
        if hidden, now - lastAssert < 0.2 { return }
        if hidden { CGDisplayShowCursor(CGMainDisplayID()) }
        let rc = CGDisplayHideCursor(CGMainDisplayID())
        if !hidden { AppLog.info("cursor", "hide asserted rc=\(rc.rawValue)") }
        hidden = true
        lastAssert = now
    }

    private func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }

    // MARK: - Parking
    //
    // Background apps can't reliably keep the cursor hidden (the WindowServer
    // re-shows it whenever it moves, and hides don't always stick even at
    // rest). What CAN'T fail: putting the arrow where it can't be seen. After
    // touch activity goes quiet, warp it to the Edge's bottom-right corner —
    // the arrow body clips off-screen there. A real mouse move cancels this.

    private var parkTimer: Timer?

    fileprivate func parkNow() {
        cancelPark()
        // Never post from inside the tap callback — events posted there are
        // dropped. Hop to the next run-loop tick.
        DispatchQueue.main.async { [weak self] in self?.park() }
    }

    fileprivate func scheduleParkAfterTouch() {
        parkTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.park() }
        }
        RunLoop.main.add(t, forMode: .common)
        parkTimer = t
    }

    fileprivate func cancelPark() {
        parkTimer?.invalidate()
        parkTimer = nil
    }

    private func park() {
        // The Edge panel's bottom-right corner, in global coordinates.
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        guard let edge = (0..<Int(count)).map({ CGDisplayBounds(ids[$0]) })
            .first(where: { abs($0.width - 2560) < 2 && abs($0.height - 720) < 2 }) else {
            AppLog.error("cursor", "park: no Edge display found")
            return
        }
        let corner = CGPoint(x: edge.maxX - 1, y: edge.maxY - 1)
        if let current = CGEvent(source: nil)?.location,
           abs(current.x - corner.x) < 2, abs(current.y - corner.y) < 2 { return }   // already parked
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.userData = kXeneonTouchEventTag
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: corner, mouseButton: .left)?.post(tap: .cgSessionEventTap)
        AppLog.info("cursor", "parked at \(Int(corner.x)),\(Int(corner.y))")
    }
}
