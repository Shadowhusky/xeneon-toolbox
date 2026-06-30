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

/// A whole-screen edge swipe the driver recognizes from raw touch positions
/// (single finger), since vertical swipes reach the app only as scroll events.
public enum SystemGesture: Sendable {
    case swipeUpFromBottom   // exit fullscreen
    case swipeDownFromTop    // drop to the minimal/idle screen
}

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

    private let debug = ProcessInfo.processInfo.environment["XENEON_TOUCH_DEBUG"] != nil
    private var reportLogCount = 0
    private var valueLogCount = 0

    var onPresenceChanged: ((Bool) -> Void)?
    var onSystemGesture: ((SystemGesture) -> Void)?

    // Edge-swipe recognition (runs alongside normal pointer handling).
    private enum Edge { case top, bottom, middle }
    private var edgeStart: (edge: Edge, y: Double)?
    private var edgeFired = false
    private let edgeMargin = 28.0
    private let edgeSwipeDistance = 190.0

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
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement],
              let xr = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageX),
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

    func deviceRemoved() {
        guard calSource != .none else { return }
        for action in recognizer.reset() { post(action) }
        for action in machine.reset() { post(action) }
        unregisterReportCallback()
        cancelMomentum()
        cancelWatchdog()
        calSource = .none
        calibration = nil
        display = nil
        digitizerActive = false
        announcedActive = false
        edgeStart = nil; edgeFired = false
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
        for action in recognizer.reset() { post(action) }
        for action in machine.reset() { post(action) }
        cancelMomentum()
        cancelWatchdog()
        unregisterReportCallback()
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
        if let first = contacts.first { lastPoint = first.point }
        feedEdge(down: !contacts.isEmpty, point: contacts.first?.point)

        for action in recognizer.update(contacts: contacts) { post(action) }

        // A finger touching cancels any coasting inertia and any momentum the
        // single→multi handoff's `.scroll(.ended)` may have just spawned.
        if !contacts.isEmpty { cancelMomentum() }
        gestureActive = !contacts.isEmpty
        rearmWatchdog()
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
        decoder.ingest(page: page, usage: usage, value: IOHIDValueGetIntegerValue(value))

        guard let cal = calibration, let disp = display, let x = decoder.rawX, let y = decoder.rawY else { return }
        if !announcedActive { announcedActive = true; onPresenceChanged?(true) }
        let point = CoordinateMapper.mapToScreen(rawX: x, rawY: y, calibration: cal, display: disp)
        lastPoint = point
        feedEdge(down: decoder.contact, point: point)
        for action in machine.update(contact: decoder.contact, point: point) { post(action) }
        gestureActive = decoder.contact   // self-cancels when a real release arrives
        rearmWatchdog()
    }

    /// Recognizes a single-finger swipe that begins at the top or bottom edge and
    /// travels far enough. Additive: it only observes, so normal taps, scrolls and
    /// drags are unaffected; it fires at most once per touch.
    private func feedEdge(down: Bool, point: ScreenPoint?) {
        guard let disp = display else { return }
        guard down, let p = point else { edgeStart = nil; edgeFired = false; return }
        if edgeStart == nil {
            let edge: Edge = p.y <= disp.y + edgeMargin ? .top
                : (p.y >= disp.y + disp.height - edgeMargin ? .bottom : .middle)
            edgeStart = (edge, p.y)
            return
        }
        guard !edgeFired, let s = edgeStart, s.edge != .middle else { return }
        let dy = p.y - s.y
        if s.edge == .top, dy > edgeSwipeDistance { edgeFired = true; onSystemGesture?(.swipeDownFromTop) }
        else if s.edge == .bottom, dy < -edgeSwipeDistance { edgeFired = true; onSystemGesture?(.swipeUpFromBottom) }
    }

    // MARK: - Event injection

    private func post(_ action: PointerAction) {
        switch action {
        case .move(let p):    postMouse(.mouseMoved, p)
        case .press(let p):   postMouse(.leftMouseDown, p)
        case .drag(let p):    postMouse(.leftMouseDragged, p)
        case .release(let p): postMouse(.leftMouseUp, p)
        case .scroll(let dx, let dy, let phase): handleScroll(dx: dx, dy: dy, phase: phase)
        case .zoom(let delta, let center): postZoom(delta, center: center)
        }
    }

    private func postMouse(_ type: CGEventType, _ p: ScreenPoint) {
        let pos = CGPoint(x: p.x, y: p.y)
        if let ev = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) {
            ev.post(tap: .cgSessionEventTap)
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
        emitScroll(dx: dx, dy: dy, scrollPhase: cgPhase, momentumPhase: 0, command: false, moveFirst: true, at: nil)
        if phase == .ended { startMomentumIfNeeded() }
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
            if speed < 45 {
                self.emitScroll(dx: dx, dy: dy, scrollPhase: 0, momentumPhase: 3, command: false, moveFirst: false, at: nil)
                t.invalidate(); self.momentumTimer = nil
                return
            }
            self.emitScroll(dx: dx, dy: dy, scrollPhase: 0,
                            momentumPhase: self.momentumFirstFrame ? 1 : 2, command: false, moveFirst: false, at: nil)
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

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, _ in
    guard let context else { return }
    Unmanaged<TouchDriver>.fromOpaque(context).takeUnretainedValue().deviceRemoved()
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
    /// Called when the Edge connects/disconnects (off the main thread).
    public var onPresenceChanged: ((Bool) -> Void)?
    /// Called when a whole-screen edge swipe is recognized (off the main thread).
    public var onSystemGesture: ((SystemGesture) -> Void)?

    private let config: TouchServiceConfig
    private let lock = NSLock()
    private var running = false
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
        driver.onSystemGesture = { [weak self] g in self?.onSystemGesture?(g) }
        let ctx = Unmanaged.passUnretained(driver).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, valueCallback, ctx)

        lock.withLock {
            self.manager = manager
            self.driver = driver
            self.running = true
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
