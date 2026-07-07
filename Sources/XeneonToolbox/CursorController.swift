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
/// alone does nothing. Enabling the `SetsCursorInBackground` connection property
/// first makes it take effect from the background — so touch input can genuinely
/// hide the cursor rather than just parking it off-screen.
///
/// Detection uses a listen-only CGEvent tap (NSEvent monitors miss pointer
/// events while inactive). The driver stamps its injected events with
/// `kXeneonTouchEventTag`; a *tagged* event is touch → hide, an *untagged* event
/// is a real pointing device → show (so the user's mouse is never lost).
@MainActor
final class CursorController {
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var cursorHidden = false
    private var parkTimer: Timer?
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
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
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
    }

    func stop() {
        showCursor()
        cancelPark()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        tapSource = nil
    }

    /// Hide the pointer (balanced — CGDisplayHideCursor uses a hide count, so we
    /// only ever hold one). Also park it off-screen as a fallback in case the
    /// background-hide is refused on some macOS build.
    private func hideCursor() {
        guard !cursorHidden else { return }
        cursorHidden = true
        CGDisplayHideCursor(CGMainDisplayID())
        parkSoon()
    }

    private func showCursor() {
        cancelPark()
        guard cursorHidden else { return }
        cursorHidden = false
        CGDisplayShowCursor(CGMainDisplayID())
    }

    private func parkSoon() {
        cancelPark()
        // Never post from inside the tap callback — hop to the next tick.
        DispatchQueue.main.async { [weak self] in self?.park() }
    }

    private func cancelPark() {
        parkTimer?.invalidate()
        parkTimer = nil
    }

    /// Warp the cursor to the Edge's bottom-right pixel, where the arrow clips
    /// out of view — a fallback if CGDisplayHideCursor is ignored. Tagged so our
    /// own event tap treats it as touch (won't re-show the cursor).
    private func park() {
        guard cursorHidden else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        guard let edge = (0..<Int(count)).map({ CGDisplayBounds(ids[$0]) })
            .first(where: { abs($0.width - 2560) < 2 && abs($0.height - 720) < 2 }) else { return }
        let corner = CGPoint(x: edge.maxX - 1, y: edge.maxY - 1)
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.userData = kXeneonTouchEventTag
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: corner, mouseButton: .left)?.post(tap: .cgSessionEventTap)
    }
}
