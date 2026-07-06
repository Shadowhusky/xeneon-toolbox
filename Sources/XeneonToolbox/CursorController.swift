import AppKit
import CoreGraphics
import XeneonTouchDriver

/// Keeps the mouse pointer out of sight while the user touches the panel.
///
/// A background app can't reliably hide the macOS cursor (CGDisplayHideCursor is
/// ignored for non-frontmost processes, and the kiosk is deliberately never
/// frontmost). What always works is *moving* it: during a touch the driver keeps
/// the cursor under the finger (covered) or off the screen corner (clipped). This
/// controller adds the finishing move — the instant a gesture ends, it parks the
/// cursor at the Edge's off-screen corner so no arrow is stranded on screen.
///
/// Detection uses a listen-only CGEvent tap: NSEvent monitors miss pointer events
/// while the app is inactive, but a HID-level tap sees everything. The driver
/// stamps its injected events with `kXeneonTouchEventTag`, so an *untagged* event
/// is a real mouse/trackpad — and we never move the user's own pointer.
@MainActor
final class CursorController {
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var parkTimer: Timer?
    private let enabled = ProcessInfo.processInfo.environment["XENEON_NOHIDECURSOR"] == nil

    func start() {
        guard enabled, tap == nil else { return }
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
            callback: { _, type, event, info in
                let controller = Unmanaged<CursorController>.fromOpaque(info!).takeUnretainedValue()
                let tagged = event.getIntegerValueField(.eventSourceUserData) == kXeneonTouchEventTag
                MainActor.assumeIsolated {
                    if tagged {
                        // Finger lifted from a tap/drag → park now; otherwise keep
                        // a short quiet-timer so scroll momentum finishes first.
                        if type == .leftMouseUp { controller.parkSoon(delay: 0) }
                        else { controller.parkSoon(delay: 0.45) }
                    } else {
                        controller.cancelPark()   // a real pointing device — leave it alone
                    }
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
        cancelPark()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        tapSource = nil
    }

    private func parkSoon(delay: TimeInterval) {
        cancelPark()
        guard delay > 0 else {
            // Never post from inside the tap callback — hop to the next tick.
            DispatchQueue.main.async { [weak self] in self?.park() }
            return
        }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.park() }
        }
        RunLoop.main.add(t, forMode: .common)
        parkTimer = t
    }

    private func cancelPark() {
        parkTimer?.invalidate()
        parkTimer = nil
    }

    /// Warp the cursor to the Edge's bottom-right pixel, where the arrow clips
    /// out of view. Tagged so our own event tap ignores it.
    private func park() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        guard let edge = (0..<Int(count)).map({ CGDisplayBounds(ids[$0]) })
            .first(where: { abs($0.width - 2560) < 2 && abs($0.height - 720) < 2 }) else { return }
        let corner = CGPoint(x: edge.maxX - 1, y: edge.maxY - 1)
        if let current = CGEvent(source: nil)?.location,
           abs(current.x - corner.x) < 2, abs(current.y - corner.y) < 2 { return }   // already parked
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.userData = kXeneonTouchEventTag
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: corner, mouseButton: .left)?.post(tap: .cgSessionEventTap)
    }
}
