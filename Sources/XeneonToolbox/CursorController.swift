import AppKit
import CoreGraphics
import XeneonTouchDriver

// Private CGS API: lets a BACKGROUND app hide/show the cursor. Without it,
// CGDisplayHideCursor is silently ignored unless the app is frontmost — and the
// kiosk now deliberately stays in the background while you touch it (so it never
// steals focus), which had brought the cursor back during touch.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: UInt32, _ target: UInt32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// Hides the pointer while the user is touching the panel, and shows it again the
/// instant a real mouse or trackpad is used. The touch driver stamps every event
/// it injects with `kXeneonTouchEventTag` (via the event source's user data), so
/// anything arriving without that tag is a physical pointing device.
@MainActor
final class CursorController {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var hidden = false
    private let enabled = ProcessInfo.processInfo.environment["XENEON_NOHIDECURSOR"] == nil

    private let mask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseDragged, .otherMouseDown, .scrollWheel,
    ]

    func start() {
        guard enabled, localMonitor == nil else { return }
        let cid = CGSMainConnectionID()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event); return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        show()
    }

    private func handle(_ event: NSEvent) {
        let tag = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
        if tag == kXeneonTouchEventTag { hide() } else { show() }
    }

    private func hide() {
        guard !hidden else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        hidden = true
    }

    private func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }
}
