import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import XeneonTouchCore

/// Stamped on every synthetic event we post (via the event source's user data),
/// so a cursor-visibility watcher can tell our touch-driven events apart from a
/// real mouse/trackpad. Read it back with
/// `CGEventGetIntegerValueField(event, .eventSourceUserData)`.
public let kXeneonTouchEventTag: Int64 = 0x58_454E_4F4E   // "XENON"

/// Phase of a continuous edge pull (driven from raw touch positions, since
/// vertical drags reach the app only as scroll events).
public enum EdgePhase: Sendable { case began, changed, ended }
public enum EdgeSide: Sendable { case top, bottom }

/// Reads the Xeneon Edge digitizer and injects pointer events. Prefers the
/// 10-finger digitizer interface (report id 0x0D) for genuine multi-touch —
/// two-finger scroll, pinch-zoom — and falls back to the device's mouse-style
/// absolute interface if those reports never arrive. Runs on the service's
/// dedicated thread, so heavy UI work on the main thread can never starve it.
///
/// All mutable state is touched only on that one thread (HID callbacks and the
/// momentum/watchdog timers all fire on its run loop), so the unchecked Sendable
/// conformance is sound.
final class TouchDriver: @unchecked Sendable {
    private let flipX: Bool
    private let flipY: Bool
    private let swapXY: Bool
    private let preferredDisplayID: CGDirectDisplayID?
    private let smoothing: Bool
    private let momentumEnabled: Bool

    private enum CalSource { case none, mouse, digitizer }
    private var calSource: CalSource = .none
    private var calibration: AxisCalibration?
    private var display: DisplayRect?

    // Multi-touch (digitizer) path.
    private var recognizer = MultiTouchRecognizer()
    private var digitizerActive = false
    private var filters: [Int: (x: OneEuroFilter, y: OneEuroFilter)] = [:]
    private var lastReportTime: CFAbsoluteTime?
    private var lastReportDt = 1.0 / 120.0
    private var reportBuf: UnsafeMutablePointer<UInt8>?
    private let reportBufLen = 256
    private weak var reportDevice: IOHIDDevice?

    // Single-touch fallback (mouse interface), used only until a 0x0D report lands.
    private var decoder = HIDTouchDecoder()
    private var machine = TouchStateMachine()

    private var announcedActive = false
    private var lastPoint: ScreenPoint?

    // Event source: tags our synthetic events so the cursor watcher can ignore them.
    private let eventSource: CGEventSource?

    // Scroll: sub-pixel residual (so slow gestures still move) + momentum velocity.
    private var scrollAccumX = 0.0
    private var scrollAccumY = 0.0
    private var scrollVel = (x: 0.0, y: 0.0)
    private var lastScrollTime: CFAbsoluteTime?
    private var momentumVel = (x: 0.0, y: 0.0)
    private var momentumTimer: Timer?
    private var momentumFirstFrame = true

    // Watchdog: release a gesture whose final "up" report we never saw.
    private var watchdogTimer: Timer?
    private var gestureActive = false

    // After a gesture the pointer goes back to where it was before the finger
    // landed, so a tap on the strip never strands the cursor away from the
    // display the user is working on.
    private var cursorReturn = CursorReturn()
    private var pointerLocation: ScreenPoint? {
        CGEvent(source: nil).map { ScreenPoint(x: $0.location.x, y: $0.location.y) }
    }

    private let debug = ProcessInfo.processInfo.environment["XENEON_TOUCH_DEBUG"] != nil
    private var reportLogCount = 0
    private var valueLogCount = 0

    var onPresenceChanged: ((Bool) -> Void)?
    /// Per-DEVICE seize result — true/false when a digitizer connects, nil when
    /// it's removed (unknown until the next connect).
    var onSeizeState: ((Bool?) -> Void)?
    var onShadePull: ((Double, EdgePhase) -> Void)?    // top-edge pull-down, left/centre (full → minimal)
    var onControlPull: ((Double, EdgePhase) -> Void)?  // top-edge pull-down, right third (control centre)
    var onBottomPull: ((Double, EdgePhase) -> Void)?   // bottom-edge pull-up (dismiss / exit)
    var onSwipeApp: ((Bool) -> Void)?                  // side-edge swipe inward — true = next app
    var onLongPress: ((ScreenPoint) -> Void)?          // finger held still — screen point (top-left global)
    var onReport: ((CFAbsoluteTime) -> Void)?          // any HID report seen (liveness for diagnostics)
    var onEdgeSlide: ((EdgeSide, Double, EdgePhase) -> Void)?   // a slide along the top/bottom edge — travel as a fraction of the width
    var onRawTouches: (([RawTouch]) -> Void)?          // fingers inside a raw region (empty = all lifted)
    var rawRouter = RawTouchRouter()
    var sideSwipeEnabled = false                       // app-switch swipes (set true in fullscreen)
    var longPressEnabled = false                       // detect long-press (set true only on the deck)

    // Long-press: a single stationary contact held past the detector's duration
    // fires onLongPress and swallows the rest of that touch (no click), for the
    // deck's "open on which screen" menu. Cheap no-op unless longPressEnabled.
    private var longPress = LongPressDetector()

    /// Returns true while a long-press owns this contact — the caller then
    /// swallows the frame so no click/scroll is emitted underneath it. An engaged
    /// press keeps ownership until the finger lifts even if `longPressEnabled` is
    /// switched off mid-gesture (the app disables detection the instant the menu
    /// opens); otherwise the still-down finger's release would leak through as a
    /// tap and dismiss the menu it just opened.
    private func feedLongPress(count: Int, point: ScreenPoint?) -> Bool {
        guard onLongPress != nil else { longPress.reset(); return false }
        switch longPress.update(enabled: longPressEnabled, count: count, point: point,
                                now: CFAbsoluteTimeGetCurrent()) {
        case .none:
            return false
        case .swallow:
            return true
        case .fire(let s):
            for action in machine.reset() { post(action) }        // cancel the pending tap
            for action in recognizer.reset() { post(action) }
            onLongPress?(s)
            return true
        }
    }
    // Edit-mode reordering: any single-finger move = mouse drag. Like
    // sideSwipeEnabled this is written from the app thread but only *read* on the
    // HID thread (applied to the state machines there, so they're never mutated
    // cross-thread mid-gesture).
    var dragAnywhereEnabled = false

    // Edge gestures (run alongside normal pointer handling). Once one engages, the
    // contact's normal pointer/scroll events are suppressed so the page underneath
    // doesn't also scroll.
    private enum EdgeKind { case none, middle, top, bottom, left, right }
    private var edgeKind: EdgeKind = .none
    private var edgeStartY = 0.0
    private var edgeStartX = 0.0
    private var edgeStartXFrac = 0.0
    private var lastDX = 0.0
    private var lastFraction = 0.0
    private var topActive = false
    private var topControl = false      // this top pull started in the right third
    private var bottomActive = false
    private var sideActive = false
    private var slideActive = false
    private var slideEligible = false   // the touch began in the thin band right at the edge
    private var lastSlide = 0.0
    private var edgeSuppress = false    // an edge gesture has engaged — drop pointer events
    private var edgeCancelled = false   // already flushed the in-flight pointer gesture
    // Touch-down anchor + release velocity, so classification tolerates a stale
    // first sample and commits project forward on a flick (iOS-style).
    private var edgeAnchored = false
    private var edgeAnchorX = 0.0, edgeAnchorY = 0.0, edgeAnchorTime = 0.0
    private var edgeVelX = 0.0, edgeVelY = 0.0
    private var edgeVelTime = 0.0, edgeVelX0 = 0.0, edgeVelY0 = 0.0
    private let edgeMargin = 84.0       // how close to an edge a touch must start
    private let edgeActivate = 10.0     // travel before a pull engages
    private let slideBand = 26.0        // edge sliders only start right at the glass edge
    private let appSwipeDistance = 80.0  // inward travel to switch apps
    private let edgeGraceTime = 0.14    // window to still catch an edge after a stale first sample
    private let edgeGraceDist = 64.0
    private let flickVelocity = 500.0   // px/s — a flick commits regardless of distance
    private let projectTime = 0.30      // seconds of velocity to project a release forward

    init(verbose: Bool, flipX: Bool, flipY: Bool, swapXY: Bool, preferredDisplayID: CGDirectDisplayID?) {
        self.flipX = flipX
        self.flipY = flipY
        self.swapXY = swapXY
        self.preferredDisplayID = preferredDisplayID
        let env = ProcessInfo.processInfo.environment
        self.smoothing = env["XENEON_TOUCH_NOSMOOTH"] == nil
        self.momentumEnabled = env["XENEON_TOUCH_NOMOMENTUM"] == nil
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.userData = kXeneonTouchEventTag
        self.eventSource = src
    }

    // MARK: - Device lifecycle

    func deviceConnected(_ device: IOHIDDevice) {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else {
            touchDiag("deviceConnected: no elements on this interface")
            return
        }
        // Try before the X/Y guard: the mode feature can live on a configuration
        // collection that carries no axes at all.
        enableMultiTouchMode(device, elements: elements)
        guard let xr = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageX),
              let yr = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageY) else {
            touchDiag("deviceConnected: no X/Y range on this interface")
            return
        }
        // The digitizer collection carries contact-id / finger elements on the
        // Digitizer usage page (0x0D); the plain mouse interface does not.
        let isDigitizer = elements.contains {
            IOHIDElementGetUsagePage($0) == 0x0D &&
            (IOHIDElementGetUsage($0) == 0x51 || IOHIDElementGetUsage($0) == 0x22)
        }

        if isDigitizer {
            calibration = AxisCalibration(minX: xr.0, maxX: xr.1, minY: yr.0, maxY: yr.1,
                                          flipX: flipX, flipY: flipY, swapXY: swapXY)
            calSource = .digitizer
            display = findEdgeDisplay(preferred: preferredDisplayID)
            registerReportCallback(device)
            // A device the long-lived manager REmatches after the panel
            // re-enumerates (sleep/wake, replug) is not reliably re-seized —
            // macOS's HID driver ends up co-driving it as a trackpad while the
            // stale manager-level flag still says "seized", so recovery never
            // fired (the toggle-Touch-to-fix bug). Seize THIS device explicitly:
            // re-opening what we already hold is harmless, and when we don't
            // hold it the seize evicts the system driver.
            let sr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            touchDiag(String(format: "device seize -> 0x%08X (%@)", sr, sr == kIOReturnSuccess ? "OK" : "fail"))
            onSeizeState?(sr == kIOReturnSuccess)
            touchDiag("digitizer connected: X[\(xr.0),\(xr.1)] Y[\(yr.0),\(yr.1)] edge=\(display != nil)")
            onPresenceChanged?(display != nil)
        } else if calSource != .digitizer {
            // Mouse interface — only adopt it as a fallback if no digitizer yet.
            calibration = AxisCalibration(minX: xr.0, maxX: xr.1, minY: yr.0, maxY: yr.1,
                                          flipX: flipX, flipY: flipY, swapXY: swapXY)
            calSource = .mouse
            display = findEdgeDisplay(preferred: preferredDisplayID)
            touchDiag("mouse interface connected (fallback): X[\(xr.0),\(xr.1)] Y[\(yr.0),\(yr.1)]")
            onPresenceChanged?(display != nil)
        }
    }

    /// Windows-Precision touch controllers often ship in mouse-emulation and only
    /// stream parallel multi-touch (report 0x0D) once the host sets the HID
    /// Digitizer "Device Mode" feature (usage 0x0D/0x52) to multi-input (2).
    /// Windows does this on enumeration; macOS never does — which is why the
    /// digitizer collection stays silent and we fall back to single-finger mouse
    /// reports. Best-effort: harmless on interfaces without the feature.
    private func enableMultiTouchMode(_ device: IOHIDDevice, elements: [IOHIDElement]) {
        for el in elements where IOHIDElementGetType(el) == kIOHIDElementTypeFeature
            && IOHIDElementGetUsagePage(el) == 0x0D
            && IOHIDElementGetUsage(el) == 0x52 {
            let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, 0, 2)   // 2 = multi-input
            let r = IOHIDDeviceSetValue(device, el, value)
            touchDiag(String(format: "multi-touch: Device Mode=2 on feature report %d -> %@",
                             IOHIDElementGetReportID(el),
                             r == kIOReturnSuccess ? "OK" : String(format: "0x%08X", r)))
        }
    }

    /// Re-read where the Edge sits. Display arrangement and mode changes move the
    /// panel's global rect without touching the HID device, so a rect captured at
    /// connect time silently maps every tap to the wrong place until a rebuild.
    func refreshDisplay() {
        guard calSource != .none else { return }
        let fresh = findEdgeDisplay(preferred: preferredDisplayID)
        guard fresh != display else { return }
        let hadDisplay = display != nil
        display = fresh
        touchDiag("display rect → " + (fresh.map { "\(Int($0.x)),\(Int($0.y)) \(Int($0.width))x\(Int($0.height))" } ?? "none"))
        if fresh == nil { onPresenceChanged?(false) }
        else if !hadDisplay { onPresenceChanged?(true) }
    }

    func deviceRemoved(_ device: IOHIDDevice) {
        guard calSource != .none else { return }
        // The WCH controller exposes several HID interfaces. Losing a secondary one
        // (the mouse-style interface re-enumerating) must not tear down a live
        // digitizer — that tear-down, with no re-match to follow, left the panel
        // dead until the user re-toggled touch.
        if calSource == .digitizer, let live = reportDevice, live !== device {
            touchDiag("secondary HID interface removed — digitizer kept")
            return
        }
        onSeizeState?(nil)
        for action in recognizer.reset() { post(action) }
        for action in machine.reset() { post(action) }
        longPress.reset()
        unregisterReportCallback()
        cancelMomentum()
        cancelWatchdog()
        calSource = .none
        calibration = nil
        display = nil
        digitizerActive = false
        announcedActive = false
        edgeKind = .none; topActive = false; topControl = false; bottomActive = false
        filters.removeAll()
        decoder = HIDTouchDecoder()
        onPresenceChanged?(false)
    }

    private func registerReportCallback(_ device: IOHIDDevice) {
        if reportBuf == nil {
            reportBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufLen)
            reportBuf!.initialize(repeating: 0, count: reportBufLen)
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuf!, reportBufLen, inputReportCallback, ctx)
        // Input-report callbacks need the device itself scheduled on this run loop;
        // the manager's scheduling alone only drives value/matching callbacks.
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        reportDevice = device
    }

    private func unregisterReportCallback() {
        if let device = reportDevice, let buf = reportBuf {
            IOHIDDeviceRegisterInputReportCallback(device, buf, reportBufLen, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        }
        reportDevice = nil
        if let buf = reportBuf { buf.deinitialize(count: reportBufLen); buf.deallocate(); reportBuf = nil }
    }

    /// Release anything held (button down, open scroll) — called on stop or
    /// device loss so a touch in progress can't leave the mouse stuck.
    func releaseHeld() {
        if rawRouter.reset() { onRawTouches?([]) }
        for action in recognizer.reset() { post(action) }
        for action in machine.reset() { post(action) }
        longPress.reset()
        cancelMomentum()
        cancelWatchdog()
        returnPointer()
        unregisterReportCallback()
    }

    /// A real mouse or trackpad moved: the user owns the pointer, so don't send it
    /// back when the current touch ends.
    func realPointerMoved() { cursorReturn.realPointerMoved() }

    /// Ends the report: tracks whether a gesture is live, and once every finger has
    /// lifted (and nothing is coasting) sends the pointer home.
    private func finishReport(contact: Bool) {
        gestureActive = contact
        rearmWatchdog()
        if !contact && momentumTimer == nil { returnPointer() }
    }

    private func returnPointer() {
        guard let home = cursorReturn.destination() else { return }
        postMouse(.mouseMoved, home)   // tagged, so the arrow stays hidden until a real device moves it
    }

    // MARK: - Digitizer (multi-touch) path

    func handleReport(reportID: UInt32, raw: [UInt8]) {
        if debug && reportLogCount < 5 {
            reportLogCount += 1
            touchDiag("input report cb: idArg=\(reportID) len=\(raw.count) head=\(raw.prefix(8).map { String(format: "%02x", $0) }.joined())")
        }
        // Some macOS releases pass reportID==0 and put the id in the first byte.
        let id: UInt8 = reportID != 0 ? UInt8(truncatingIfNeeded: reportID) : (raw.first ?? 0)
        guard id == DigitizerReport.reportID, let cal = calibration, let disp = display else { return }
        // Strip the leading report-id byte when present (full report is 53 payload bytes).
        let payload: [UInt8] = raw.count >= 54 ? Array(raw.dropFirst()) : raw

        if !digitizerActive {
            digitizerActive = true
            for action in machine.reset() { post(action) }   // flush any half-finished fallback gesture
            decoder = HIDTouchDecoder()
            touchDiag("digitizer multi-touch path live")
        }

        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastReportTime.map { max(0.0001, now - $0) } ?? (1.0 / 120.0)
        lastReportTime = now
        lastReportDt = dt
        onReport?(now)

        let raws = DigitizerReport.parse(payload: payload)
        if !raws.isEmpty && !announcedActive { announcedActive = true; onPresenceChanged?(true) }

        var seen = Set<Int>()
        var contacts: [TouchContact] = []
        contacts.reserveCapacity(raws.count)
        for rc in raws {
            seen.insert(rc.id)
            let mapped = CoordinateMapper.mapToScreen(rawX: Double(rc.x), rawY: Double(rc.y), calibration: cal, display: disp)
            let point: ScreenPoint
            if smoothing {
                var f = filters[rc.id] ?? (OneEuroFilter(), OneEuroFilter())
                point = ScreenPoint(x: f.x.filter(mapped.x, dt: dt), y: f.y.filter(mapped.y, dt: dt))
                filters[rc.id] = f
            } else {
                point = mapped
            }
            contacts.append(TouchContact(id: rc.id, point: point))
        }
        filters = filters.filter { seen.contains($0.key) }
        let routed = rawRouter.route(contacts)
        if let raw = routed.raw { onRawTouches?(raw) }
        contacts = routed.pointer
        if let first = contacts.first { lastPoint = first.point }
        if !contacts.isEmpty && !gestureActive { cursorReturn.touchBegan(pointerAt: pointerLocation) }
        feedEdge(down: !contacts.isEmpty, point: contacts.first?.point)

        // Once an edge gesture engages, swallow this contact's pointer/scroll so the
        // page underneath doesn't scroll along with the swipe.
        if edgeSuppress {
            if !edgeCancelled { for action in recognizer.reset() { post(action) }; edgeCancelled = true }
            cancelMomentum()
            finishReport(contact: !contacts.isEmpty)
            return
        }
        edgeCancelled = false

        if feedLongPress(count: contacts.count, point: contacts.first?.point) {
            finishReport(contact: !contacts.isEmpty)
            return
        }

        recognizer.dragAnywhere = dragAnywhereEnabled
        for action in recognizer.update(contacts: contacts) { post(action) }

        // A finger touching cancels any coasting inertia and any momentum the
        // single→multi handoff's `.scroll(.ended)` may have just spawned.
        if !contacts.isEmpty { cancelMomentum() }
        finishReport(contact: !contacts.isEmpty)
    }

    // MARK: - Mouse fallback path

    func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        if debug && valueLogCount < 16 {
            valueLogCount += 1
            touchDiag(String(format: "value cb: page=0x%02X usage=0x%02X value=%ld", page, usage, IOHIDValueGetIntegerValue(value)))
        }
        guard !digitizerActive else { return }   // digitizer owns input once live
        onReport?(CFAbsoluteTimeGetCurrent())
        decoder.ingest(page: page, usage: usage, value: IOHIDValueGetIntegerValue(value))

        guard let cal = calibration, let disp = display, let x = decoder.rawX, let y = decoder.rawY else { return }
        if !announcedActive { announcedActive = true; onPresenceChanged?(true) }
        let point = CoordinateMapper.mapToScreen(rawX: x, rawY: y, calibration: cal, display: disp)
        lastPoint = point
        if decoder.contact && !gestureActive { cursorReturn.touchBegan(pointerAt: pointerLocation) }
        feedEdge(down: decoder.contact, point: point)
        if edgeSuppress {
            if !edgeCancelled { for action in machine.reset() { post(action) }; edgeCancelled = true }
            finishReport(contact: decoder.contact)
            return
        }
        edgeCancelled = false
        if feedLongPress(count: decoder.contact ? 1 : 0, point: decoder.contact ? point : nil) {
            finishReport(contact: decoder.contact)
            return
        }
        machine.dragAnywhere = dragAnywhereEnabled
        for action in machine.update(contact: decoder.contact, point: point) { post(action) }
        finishReport(contact: decoder.contact)   // self-cancels when a real release arrives
    }

    /// Observes the primary finger for edge gestures (additive — taps, scrolls and
    /// drags still run normally underneath). A touch starting at the top edge and
    /// moving down streams a continuous "shade" pull (the app follows it with the
    /// minimal screen); a touch at the bottom edge moving up fires once to exit
    /// fullscreen.
    private func feedEdge(down: Bool, point: ScreenPoint?) {
        guard let disp = display else { return }
        let h = max(1, disp.height), w = max(1, disp.width)
        guard down, let p = point else {
            // Project the release forward by its velocity so a quick flick commits
            // even from a short drag (UIScrollView-style deceleration projection).
            let projected = min(1, max(0, lastFraction + (edgeVelY / h) * projectTime))
            if topActive { (topControl ? onControlPull : onShadePull)?(projected, .ended) }
            if bottomActive { onBottomPull?(projected, .ended) }
            if slideActive { onEdgeSlide?(edgeKind == .top ? .top : .bottom, lastSlide, .ended) }
            if sideActive {
                if edgeKind == .left, lastDX > appSwipeDistance || edgeVelX > flickVelocity { onSwipeApp?(false) }
                else if edgeKind == .right, -lastDX > appSwipeDistance || -edgeVelX > flickVelocity { onSwipeApp?(true) }
            }
            edgeKind = .none; topActive = false; topControl = false; bottomActive = false; sideActive = false
            slideActive = false; slideEligible = false
            edgeSuppress = false; edgeAnchored = false
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        let localX = p.x - disp.x
        let localY = p.y - disp.y
        let frac = min(1, max(0, localY / h))
        lastFraction = frac

        // Anchor the touch on first contact; track a velocity EMA over ~30ms windows.
        if !edgeAnchored {
            edgeAnchored = true
            edgeAnchorX = p.x; edgeAnchorY = p.y; edgeAnchorTime = now
            edgeVelX = 0; edgeVelY = 0; edgeVelTime = now; edgeVelX0 = p.x; edgeVelY0 = p.y
        } else if now - edgeVelTime > 0.03 {
            let dt = now - edgeVelTime
            edgeVelX = 0.6 * ((p.x - edgeVelX0) / dt) + 0.4 * edgeVelX
            edgeVelY = 0.6 * ((p.y - edgeVelY0) / dt) + 0.4 * edgeVelY
            edgeVelTime = now; edgeVelX0 = p.x; edgeVelY0 = p.y
        }

        if edgeKind == .none {
            // Classify against the current point. Tolerate a stale first sample by
            // staying undecided (not locking to `.middle`) until the touch has
            // clearly moved inward or the grace window has elapsed.
            if localY <= edgeMargin {
                edgeKind = .top; edgeStartY = p.y; edgeStartX = p.x; edgeStartXFrac = localX / w
                slideEligible = localY <= slideBand
            } else if localY >= h - edgeMargin {
                edgeKind = .bottom; edgeStartY = p.y; edgeStartX = p.x
                slideEligible = localY >= h - slideBand
            // No side swipes while a grid is in edit mode (dragAnywhereEnabled) —
            // dragging a tile from near a screen edge must not switch apps.
            } else if sideSwipeEnabled, !dragAnywhereEnabled, localX <= edgeMargin {
                edgeKind = .left; edgeStartX = p.x; lastDX = 0
            } else if sideSwipeEnabled, !dragAnywhereEnabled, localX >= w - edgeMargin {
                edgeKind = .right; edgeStartX = p.x; lastDX = 0
            } else if now - edgeAnchorTime > edgeGraceTime || hypot(p.x - edgeAnchorX, p.y - edgeAnchorY) > edgeGraceDist {
                edgeKind = .middle
            }
            return
        }
        if slideActive {
            lastSlide = (p.x - edgeStartX) / w
            onEdgeSlide?(edgeKind == .top ? .top : .bottom, lastSlide, .changed)
            return
        }
        if (edgeKind == .top || edgeKind == .bottom), !topActive, !bottomActive, !dragAnywhereEnabled {
            let inward = edgeKind == .top ? p.y - edgeStartY : edgeStartY - p.y
            if EdgeSlide.decide(along: p.x - edgeStartX, inward: inward, startedInBand: slideEligible, pullActivate: edgeActivate) == .slide {
                slideActive = true; edgeSuppress = true
                edgeStartX = p.x; lastSlide = 0   // measure from where the slide engaged, so the level doesn't jump
                onEdgeSlide?(edgeKind == .top ? .top : .bottom, 0, .began)
                return
            }
        }
        switch edgeKind {
        case .top:
            if topActive {
                (topControl ? onControlPull : onShadePull)?(frac, .changed)
            } else if p.y - edgeStartY > edgeActivate {
                topActive = true
                topControl = edgeStartXFrac > 0.66
                (topControl ? onControlPull : onShadePull)?(frac, .began)
            }
        case .bottom:
            if bottomActive { onBottomPull?(frac, .changed) }
            else if edgeStartY - p.y > edgeActivate { bottomActive = true; onBottomPull?(frac, .began) }
        case .left, .right:
            lastDX = p.x - edgeStartX
            if !sideActive, abs(lastDX) > edgeActivate { sideActive = true }
        default:
            break
        }
        edgeSuppress = topActive || bottomActive || sideActive
    }

    // MARK: - Event injection

    // Where a hover .move would have put the cursor. Standalone moves are NOT
    // posted: a background app can't keep the cursor hidden while it's moving
    // (the WindowServer re-shows it on every motion), so the finger no longer
    // drags a visible arrow around. Clicks carry their own position; scroll
    // bursts get ONE position sync first so they dispatch to the right window.
    private var pendingCursorSync: ScreenPoint?

    private func post(_ action: PointerAction) {
        switch action {
        case .move(let p):
            pendingCursorSync = p
        case .press(let p):
            pendingCursorSync = nil
            postMouse(.leftMouseDown, p)
        case .drag(let p):    postMouse(.leftMouseDragged, p)
        case .release(let p):
            postMouse(.leftMouseUp, p)
            // Leave the tap point in this same cycle: back to where the pointer was
            // before the finger landed, or the off-screen corner when that's
            // unknown. Parking only via the async CursorController leaves the arrow
            // blinking at the tap point for a frame; doing it here means
            // WindowServer composites just once, with the cursor already away.
            if let home = cursorReturn.destination() { postMouse(.mouseMoved, home) }
            else if let c = parkCorner { postMouse(.mouseMoved, c) }
        case .scroll(let dx, let dy, let phase):
            if phase == .began, let sync = pendingCursorSync {
                postMouse(.mouseMoved, sync)   // scrolls follow the pointer — place it once
                pendingCursorSync = nil
            }
            handleScroll(dx: dx, dy: dy, phase: phase)
        case .zoom(let delta, let center):
            if let sync = pendingCursorSync {
                postMouse(.mouseMoved, sync)
                pendingCursorSync = nil
            }
            postZoom(delta, center: center)
        }
    }

    private func postMouse(_ type: CGEventType, _ p: ScreenPoint) {
        let pos = CGPoint(x: p.x, y: p.y)
        if let ev = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) {
            ev.post(tap: .cgSessionEventTap)
            cursorReturn.posted()
        }
    }

    private func handleScroll(dx: Double, dy: Double, phase: ScrollPhase) {
        let now = CFAbsoluteTimeGetCurrent()
        switch phase {
        case .began:
            scrollVel = (0, 0); lastScrollTime = now
            scrollAccumX = 0; scrollAccumY = 0
        case .changed:
            if let t = lastScrollTime {
                let d = max(lastReportDt, now - t)   // real report interval, not post-time
                let inst = (dx / d, dy / d)
                scrollVel = (0.5 * inst.0 + 0.5 * scrollVel.0, 0.5 * inst.1 + 0.5 * scrollVel.1)
            }
            lastScrollTime = now
        case .ended:
            break
        }
        let cgPhase: Int64 = phase == .began ? 1 : (phase == .changed ? 2 : 4)
        // The scroll's .location moves the visible cursor. During an active scroll
        // that's the finger point (under the finger, hidden by it). On the closing
        // .ended event — finger already lifted — route at the off-screen corner so
        // no arrow is left sitting on screen while momentum coasts.
        let at: ScreenPoint? = phase == .ended ? parkCorner : nil
        emitScroll(dx: dx, dy: dy, scrollPhase: cgPhase, momentumPhase: 0, command: false, moveFirst: true, at: at)
        if phase == .ended { startMomentumIfNeeded() }
    }

    /// The Edge's bottom-right pixel — off-screen enough that the cursor's arrow
    /// clips out of view. Momentum and gesture-end events route here so no visible
    /// pointer is stranded when the finger lifts.
    private var parkCorner: ScreenPoint? {
        display.map { ScreenPoint(x: $0.x + $0.width - 1, y: $0.y + $0.height - 1) }
    }

    /// Pinch → page zoom. The browser's web view treats a Command-modified scroll
    /// as zoom, anchored at the midpoint between the two fingers; nothing else
    /// reacts, which is the intended behaviour.
    private func postZoom(_ delta: Double, center: ScreenPoint) {
        emitScroll(dx: 0, dy: delta * 0.5, scrollPhase: 0, momentumPhase: 0, command: true, moveFirst: true, at: center)
    }

    private func emitScroll(dx: Double, dy: Double, scrollPhase: Int64, momentumPhase: Int64,
                            command: Bool, moveFirst: Bool, at: ScreenPoint?) {
        let loc = at ?? lastPoint
        if moveFirst, let p = loc { postMouse(.mouseMoved, p) }
        // Carry the sub-pixel remainder so slow gestures still scroll/zoom.
        scrollAccumX += dx; scrollAccumY += dy
        let wy = scrollAccumY.rounded(.towardZero), wx = scrollAccumX.rounded(.towardZero)
        scrollAccumY -= wy; scrollAccumX -= wx
        guard let ev = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel,
                               wheelCount: 2, wheel1: Int32(wy), wheel2: Int32(wx), wheel3: 0) else { return }
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if scrollPhase != 0 { ev.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase) }
        if momentumPhase != 0 { ev.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase) }
        if command { ev.flags = .maskCommand }
        if let p = loc { ev.location = CGPoint(x: p.x, y: p.y) }
        ev.post(tap: .cgSessionEventTap)
        if loc != nil { cursorReturn.posted() }
    }

    // MARK: - Momentum

    private func startMomentumIfNeeded() {
        guard momentumEnabled else { return }
        let speed = hypot(scrollVel.x, scrollVel.y)   // px/sec
        guard speed > 220 else { return }
        momentumVel = scrollVel
        momentumFirstFrame = true
        cancelMomentum()
        let frame = 1.0 / 60.0
        let timer = Timer(timeInterval: frame, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.momentumVel = (self.momentumVel.x * 0.93, self.momentumVel.y * 0.93)
            let speed = hypot(self.momentumVel.x, self.momentumVel.y)
            let dx = self.momentumVel.x * frame, dy = self.momentumVel.y * frame
            // Route momentum at the off-screen corner: the finger is gone, so
            // pinning the scroll's .location (and thus the cursor) at the lift
            // point would leave a visible arrow coasting on screen.
            let corner = self.parkCorner
            if speed < 45 {
                self.emitScroll(dx: dx, dy: dy, scrollPhase: 0, momentumPhase: 3, command: false, moveFirst: false, at: corner)
                t.invalidate(); self.momentumTimer = nil
                if !self.gestureActive { self.returnPointer() }
                return
            }
            self.emitScroll(dx: dx, dy: dy, scrollPhase: 0,
                            momentumPhase: self.momentumFirstFrame ? 1 : 2, command: false, moveFirst: false, at: corner)
            self.momentumFirstFrame = false
        }
        RunLoop.current.add(timer, forMode: .common)
        momentumTimer = timer
    }

    private func cancelMomentum() {
        momentumTimer?.invalidate(); momentumTimer = nil
    }

    // MARK: - Watchdog

    private func rearmWatchdog() {
        watchdogTimer?.invalidate(); watchdogTimer = nil
        guard gestureActive else { return }
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self else { return }
            touchDiag("watchdog: no reports for 350ms mid-gesture — releasing")
            self.scrollVel = (0, 0)   // don't fling momentum on a watchdog release
            for action in self.recognizer.reset() { self.post(action) }
            for action in self.machine.reset() { self.post(action) }
            self.gestureActive = false
            self.filters.removeAll()
            self.cancelMomentum()
            self.returnPointer()
            // An edge swipe whose final "up" never arrived must not keep swallowing
            // the next touch's pointer events.
            self.edgeKind = .none; self.topActive = false; self.topControl = false
            self.bottomActive = false; self.sideActive = false
            self.edgeSuppress = false; self.edgeAnchored = false
        }
        RunLoop.current.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func cancelWatchdog() {
        watchdogTimer?.invalidate(); watchdogTimer = nil
    }
}

private let valueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    Unmanaged<TouchDriver>.fromOpaque(context).takeUnretainedValue().handle(value: value)
}

private let inputReportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, reportLength in
    guard let context, reportLength > 0 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
    Unmanaged<TouchDriver>.fromOpaque(context).takeUnretainedValue().handleReport(reportID: reportID, raw: bytes)
}

private let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<TouchDriver>.fromOpaque(context).takeUnretainedValue().deviceConnected(device)
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<TouchDriver>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
}

public struct TouchServiceConfig: Sendable {
    public var flipX: Bool
    public var flipY: Bool
    public var swapXY: Bool
    public var preferredDisplayID: CGDirectDisplayID?
    public var preferSeize: Bool
    public var verbose: Bool

    public init(flipX: Bool = false, flipY: Bool = false, swapXY: Bool = false,
                preferredDisplayID: CGDirectDisplayID? = nil,
                preferSeize: Bool = true, verbose: Bool = false) {
        self.flipX = flipX
        self.flipY = flipY
        self.swapXY = swapXY
        self.preferredDisplayID = preferredDisplayID
        self.preferSeize = preferSeize
        self.verbose = verbose
    }
}

/// Embeddable touch driver. `start()` opens the device, then runs the HID
/// callbacks on a dedicated high-priority thread with its own run loop — so a
/// busy main thread (heavy SwiftUI redraws, a slow DDC brightness write) can
/// never stall or freeze touch input. Safe to start/stop repeatedly: startup is
/// synchronized so a stop is never lost, and teardown is synchronous so an
/// immediate restart re-seizes the device cleanly.
public final class TouchService: @unchecked Sendable {
    public var isRunning: Bool { lock.withLock { running } }
    /// True only when we hold the digitizer EXCLUSIVELY (seized). When false, the
    /// open fell back to non-exclusive because macOS holds the device — meaning
    /// macOS also processes it as a Precision trackpad (the panel "reverts to a
    /// touchpad"). The app watches this to retry the seize.
    public var isSeized: Bool { lock.withLock { running && (deviceSeized ?? seized) } }
    /// Seize result of the currently-connected digitizer DEVICE (nil = none
    /// connected / unknown). The manager-level flag goes stale when the panel
    /// re-enumerates; this one is refreshed on every connect.
    private var deviceSeized: Bool?
    /// Called when the Edge connects/disconnects (off the main thread).
    public var onPresenceChanged: ((Bool) -> Void)?
    /// Per-device seize result on each digitizer connect (nil on removal).
    public var onSeizeState: ((Bool?) -> Void)?
    /// Called continuously during a top-edge pull-down, left/centre (off the main thread).
    public var onShadePull: ((Double, EdgePhase) -> Void)?
    /// Called continuously during a top-edge pull-down in the right third (off the main thread).
    public var onControlPull: ((Double, EdgePhase) -> Void)?
    /// Called continuously during a bottom-edge pull-up (off the main thread).
    public var onBottomPull: ((Double, EdgePhase) -> Void)?
    /// Called once when a side edge is swiped inward — true = next app (off the main thread).
    public var onSwipeApp: ((Bool) -> Void)?
    /// Called when a finger is held still on the deck — the screen point (off the main thread).
    public var onLongPress: ((ScreenPoint) -> Void)?
    /// A slide along the top or bottom edge: travel so far as a fraction of the
    /// panel's width, signed (off the main thread).
    public var onEdgeSlide: ((EdgeSide, Double, EdgePhase) -> Void)?
    /// Fingers inside a raw region, every report while any are down, then one
    /// empty list when the last lifts (off the main thread).
    public var onRawTouches: (([RawTouch]) -> Void)?
    /// Parts of the panel whose touches skip the pointer and arrive through
    /// `onRawTouches`, so a view can track several fingers at once.
    public func setRawRegions(_ regions: [RawRegion]) {
        lock.withLock { rawRegions = regions }
        onDriverThread { $0.rawRouter.regions = regions }
    }
    private var rawRegions: [RawRegion] = []
    /// Enables the left/right edge app-switch swipes (set true only in fullscreen).
    public var sideSwipeEnabled = false {
        didSet { lock.withLock { driver?.sideSwipeEnabled = sideSwipeEnabled } }
    }
    /// Enables long-press detection (set true only while the deck is interactive).
    public var longPressEnabled = false {
        didSet { lock.withLock { driver?.longPressEnabled = longPressEnabled } }
    }
    /// While a grid is in edit mode, any single-finger move becomes a mouse drag
    /// (instead of vertical/diagonal moves turning into scroll events with no
    /// press) — this is what makes drag-to-reorder possible on a 2-D grid.
    public var dragAnywhereEnabled = false {
        didSet { lock.withLock { driver?.dragAnywhereEnabled = dragAnywhereEnabled } }
    }

    /// Release anything the pointer state machine is still holding (a mouse
    /// button left down by a missed touch-up, a half-open scroll). Runs on the
    /// driver's own thread. Call when the UI changes interaction modes so a
    /// stuck press can never deaden the whole panel.
    public func flushPointer() {
        onDriverThread { $0.releaseHeld() }
    }

    /// Tell the driver a real mouse or trackpad moved, so a touch in progress
    /// won't send the pointer back to where it was when the finger landed.
    public func realPointerMoved() {
        onDriverThread { $0.realPointerMoved() }
    }

    /// Re-read the Edge's global rect (display arrangement or mode changed) without
    /// tearing the driver down. Cheap; safe to call on every watchdog tick.
    public func refreshDisplay() {
        onDriverThread { $0.refreshDisplay() }
    }

    /// When the digitizer last delivered any report — "last input 4 s ago" in
    /// Settings, so a silent driver can be told apart from an idle user.
    public var lastReportAt: Date? {
        lock.withLock { lastReport.map { Date(timeIntervalSinceReferenceDate: $0) } }
    }
    private var lastReport: CFAbsoluteTime?

    private func onDriverThread(_ work: @escaping (TouchDriver) -> Void) {
        let (drv, rl): (TouchDriver?, CFRunLoop?) = lock.withLock { (driver, runLoop) }
        guard let drv, let rl else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { work(drv) }
        CFRunLoopWakeUp(rl)
    }

    private let config: TouchServiceConfig
    private let lock = NSLock()
    private var running = false
    private var seized = false
    private var manager: IOHIDManager?
    private var driver: TouchDriver?
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    public init(config: TouchServiceConfig = .init()) {
        self.config = config
    }

    @discardableResult
    public func start() -> Bool {
        if lock.withLock({ running }) { return true }
        guard let (manager, seized) = openManager(preferSeize: config.preferSeize) else { return false }
        if config.verbose || ProcessInfo.processInfo.environment["XENEON_TOUCH_DEBUG"] != nil {
            warn("TOUCH: HID manager opened, seized=\(seized)\n")
        }

        let driver = TouchDriver(verbose: config.verbose,
                                 flipX: config.flipX, flipY: config.flipY, swapXY: config.swapXY,
                                 preferredDisplayID: config.preferredDisplayID)
        driver.onPresenceChanged = { [weak self] present in self?.onPresenceChanged?(present) }
        driver.onSeizeState = { [weak self] s in
            guard let self else { return }
            self.lock.withLock { self.deviceSeized = s }
            self.onSeizeState?(s)
        }
        driver.onShadePull = { [weak self] f, p in self?.onShadePull?(f, p) }
        driver.onControlPull = { [weak self] f, p in self?.onControlPull?(f, p) }
        driver.onBottomPull = { [weak self] f, p in self?.onBottomPull?(f, p) }
        driver.onSwipeApp = { [weak self] next in self?.onSwipeApp?(next) }
        driver.onLongPress = { [weak self] p in self?.onLongPress?(p) }
        driver.onRawTouches = { [weak self] t in self?.onRawTouches?(t) }
        driver.onEdgeSlide = { [weak self] e, f, p in self?.onEdgeSlide?(e, f, p) }
        driver.rawRouter.regions = lock.withLock { rawRegions }
        driver.onReport = { [weak self] t in
            guard let self else { return }
            self.lock.withLock { self.lastReport = t }
        }
        driver.sideSwipeEnabled = sideSwipeEnabled
        driver.dragAnywhereEnabled = dragAnywhereEnabled
        driver.longPressEnabled = longPressEnabled
        let ctx = Unmanaged.passUnretained(driver).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, valueCallback, ctx)

        lock.withLock {
            self.manager = manager
            self.driver = driver
            self.running = true
            self.seized = seized
        }

        // Publish the worker run loop before start() returns, so a stop() that
        // races in immediately always finds a non-nil run loop to tear down.
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            let rl: CFRunLoop = CFRunLoopGetCurrent()
            self.lock.withLock { self.runLoop = rl }
            IOHIDManagerScheduleWithRunLoop(manager, rl, CFRunLoopMode.commonModes.rawValue)
            ready.signal()
            CFRunLoopRun()
            IOHIDManagerUnscheduleFromRunLoop(manager, rl, CFRunLoopMode.commonModes.rawValue)
        }
        thread.name = "com.shadowhusky.xeneon.touch"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        lock.withLock { self.thread = thread }
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return true
    }

    public func stop() {
        let (mgr, drv, rl): (IOHIDManager?, TouchDriver?, CFRunLoop?) = lock.withLock {
            guard running else { return (nil, nil, nil) }
            running = false
            seized = false
            deviceSeized = nil
            defer { manager = nil; driver = nil; thread = nil; runLoop = nil }
            return (manager, driver, runLoop)
        }
        guard let mgr else { return }
        if let rl {
            // Tear down on the worker thread and wait for it, so a following start()
            // re-opens only after this seize is released (no double-seize fallback).
            let done = DispatchSemaphore(value: 0)
            CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) {
                drv?.releaseHeld()
                IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
                CFRunLoopStop(rl)
                done.signal()
            }
            CFRunLoopWakeUp(rl)
            _ = done.wait(timeout: .now() + 1)
        } else {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        onPresenceChanged?(false)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
