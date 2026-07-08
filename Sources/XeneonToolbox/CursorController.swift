import AppKit
import CoreGraphics
import XeneonTouchDriver

// Private CoreGraphics window-server calls. `SetsCursorInBackground` lets a
// non-frontmost app control cursor visibility — without it CGDisplayHideCursor
// is silently ignored for a background process (which the kiosk always is, by
// design). This is the standard technique kiosk / remote-desktop apps use.
private typealias CGSConnectionID = Int32
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: CGSConnectionID, _ target: CGSConnectionID, _ key: CFString, _ value: CFTypeRef) -> CGError

/// Hides the mouse pointer while the user touches the panel, and restores it the
/// moment a real mouse/trackpad is used.
///
/// The kiosk is deliberately never the frontmost app, so `CGDisplayHideCursor`
/// alone does nothing; enabling the `SetsCursorInBackground` connection property
/// first makes it take effect from the background.
///
/// Detection uses a listen-only CGEvent tap. IMPORTANT: it must be at the
/// **annotated-session** level, not the HID level — the driver posts its events
/// at `.cgSessionEventTap`, which is downstream of the HID tap, so an HID-level
/// listener never sees them (verified: an HID tap receives 0 of the driver's
/// events). The driver stamps its events with `kXeneonTouchEventTag`; a *tagged*
/// event is touch → hide, an *untagged* event is a real pointing device → show.
///
/// The WindowServer re-draws the hardware cursor on every pointer *motion*, and
/// the driver posts a positioned event per touch frame — so a single hide is
/// undone by the next frame. We therefore re-issue the hide on every tagged
/// event (tracking depth so a real-mouse event fully unwinds it).
@MainActor
final class CursorController {
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var hideDepth = 0
    private let enabled = ProcessInfo.processInfo.environment["XENEON_NOHIDECURSOR"] == nil

    func start() {
        guard enabled, tap == nil else { return }
        // Allow cursor control from the background (kiosk is never frontmost).
        let cid = CGSMainConnectionID()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, info in
                let controller = Unmanaged<CursorController>.fromOpaque(info!).takeUnretainedValue()
                let tagged = event.getIntegerValueField(.eventSourceUserData) == kXeneonTouchEventTag
                MainActor.assumeIsolated {
                    if tagged { controller.hideCursor() }
                    else { controller.showCursor() }   // a real pointing device — give it back
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: info) else {
            AppLog.error("cursor", "couldn't create the event tap — cursor may show during touch")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AppLog.info("cursor", "hide-on-touch active (annotated-session tap)")
    }

    func stop() {
        showCursor()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        tapSource = nil
    }

    /// Re-hide on every touch frame — the WindowServer re-shows the cursor on
    /// motion, so one hide doesn't stick. `CGDisplayHideCursor` is a counter, so
    /// track depth; a real-mouse event unwinds it fully. Depth is bounded by a
    /// single gesture's length (it resets the moment a real device is used).
    private func hideCursor() {
        CGDisplayHideCursor(CGMainDisplayID())
        hideDepth += 1
    }

    private func showCursor() {
        while hideDepth > 0 { CGDisplayShowCursor(CGMainDisplayID()); hideDepth -= 1 }
    }
}
