import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import XeneonTouchCore

/// Reads the Xeneon Edge digitizer and injects absolute pointer events. One
/// instance handles connect/disconnect for the lifetime of the manager.
final class TouchDriver {
    private let verbose: Bool
    private let flipX: Bool
    private let flipY: Bool
    private let swapXY: Bool
    private let preferredDisplayID: CGDirectDisplayID?
    private var calibration: AxisCalibration?
    private var display: DisplayRect?
    private var machine = TouchStateMachine()
    private var decoder = HIDTouchDecoder()
    private var announcedActive = false
    private var lastPoint: ScreenPoint?   // newest finger position, for scroll-event routing
    var onPresenceChanged: ((Bool) -> Void)?

    init(verbose: Bool, flipX: Bool, flipY: Bool, swapXY: Bool, preferredDisplayID: CGDirectDisplayID?) {
        self.verbose = verbose
        self.flipX = flipX
        self.flipY = flipY
        self.swapXY = swapXY
        self.preferredDisplayID = preferredDisplayID
    }

    func deviceConnected(_ device: IOHIDDevice) {
        guard calibration == nil,
              let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement],
              let xr = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageX),
              let yr = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageY) else { return }
        calibration = AxisCalibration(minX: xr.0, maxX: xr.1, minY: yr.0, maxY: yr.1,
                                      flipX: flipX, flipY: flipY, swapXY: swapXY)
        display = findEdgeDisplay(preferred: preferredDisplayID)
        decoder = HIDTouchDecoder()
        onPresenceChanged?(display != nil)
    }

    func deviceRemoved() {
        guard calibration != nil else { return }
        for action in machine.reset() { post(action) }
        calibration = nil
        display = nil
        decoder = HIDTouchDecoder()
        announcedActive = false
        onPresenceChanged?(false)
    }

    func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intVal = IOHIDValueGetIntegerValue(value)

        decoder.ingest(page: page, usage: usage, value: intVal)

        guard let cal = calibration, let disp = display,
              let x = decoder.rawX, let y = decoder.rawY else { return }

        if !announcedActive { announcedActive = true; onPresenceChanged?(true) }
        let point = CoordinateMapper.mapToScreen(rawX: x, rawY: y, calibration: cal, display: disp)
        lastPoint = point
        for action in machine.update(contact: decoder.contact, point: point) {
            post(action)
        }
    }

    /// Release any held button — called when the service stops or the device
    /// vanishes, so a touch in progress can't leave the mouse stuck down.
    func releaseHeld() {
        for action in machine.reset() { post(action) }
    }

    private func post(_ action: PointerAction) {
        switch action {
        case .move(let p):    postMouse(.mouseMoved, p)
        case .press(let p):   postMouse(.leftMouseDown, p)
        case .drag(let p):    postMouse(.leftMouseDragged, p)
        case .release(let p): postMouse(.leftMouseUp, p)
        case .scroll(let dx, let dy, let phase): postScroll(dx: dx, dy: dy, phase: phase)
        }
    }

    private func postMouse(_ type: CGEventType, _ p: ScreenPoint) {
        let pos = CGPoint(x: p.x, y: p.y)
        if let ev = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) {
            ev.post(tap: .cgSessionEventTap)
        }
    }

    /// Turn a finger drag into a *continuous* scroll-wheel event. macOS SwiftUI
    /// scroll views ignore legacy (line/pixel) wheel events and only react to
    /// continuous, phase-framed scrolls — so each gesture is a began…changed…
    /// ended sequence. wheel1 == dy makes the content track the finger (natural
    /// touch scrolling): a finger swipe up moves the content up.
    private func postScroll(dx: Double, dy: Double, phase: ScrollPhase) {
        // Keep the cursor under the finger — scroll-wheel events route to the view
        // at the pointer, so without this the content under the finger never scrolls.
        if let p = lastPoint { postMouse(.mouseMoved, p) }
        guard let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 2, wheel1: Int32(dy.rounded()),
                               wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let cgPhase: Int64 = phase == .began ? 1 : (phase == .changed ? 2 : 4)
        ev.setIntegerValueField(.scrollWheelEventScrollPhase, value: cgPhase)
        if let p = lastPoint { ev.location = CGPoint(x: p.x, y: p.y) }   // explicit hit-test point
        ev.post(tap: .cgSessionEventTap)
    }
}

private let valueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    Unmanaged<TouchDriver>.fromOpaque(context).takeUnretainedValue().handle(value: value)
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

/// Embeddable touch driver. `start()` schedules on the current run loop and
/// returns; the host's run loop drives the callbacks. Safe to start/stop
/// repeatedly (e.g. a UI toggle).
public final class TouchService {
    public private(set) var isRunning = false
    /// Called on the run loop's thread when the Edge connects/disconnects.
    public var onPresenceChanged: ((Bool) -> Void)?

    private let config: TouchServiceConfig
    private var manager: IOHIDManager?
    private var driver: TouchDriver?

    public init(config: TouchServiceConfig = .init()) {
        self.config = config
    }

    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }
        guard let (manager, _) = openManager(preferSeize: config.preferSeize) else { return false }

        let driver = TouchDriver(verbose: config.verbose,
                                 flipX: config.flipX, flipY: config.flipY, swapXY: config.swapXY,
                                 preferredDisplayID: config.preferredDisplayID)
        driver.onPresenceChanged = { [weak self] present in self?.onPresenceChanged?(present) }
        let ctx = Unmanaged.passUnretained(driver).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, valueCallback, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        self.manager = manager
        self.driver = driver
        self.isRunning = true
        return true
    }

    public func stop() {
        guard isRunning, let manager else { return }
        driver?.releaseHeld()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        self.driver = nil
        self.isRunning = false
        onPresenceChanged?(false)
    }
}
