import AppKit
import CoreGraphics
import XeneonTouchDriver

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
