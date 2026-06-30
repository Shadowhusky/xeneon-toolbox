import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import XeneonTouchCore

// Corsair Xeneon Edge touch digitizer (the WCH HID controller, not the
// Corsair iCUE control interface 0x1b1c:0x1d0d).
public let kVendorID = 0x27c0
public let kProductID = 0x0859

// HID usages we care about.
public let kPageGenericDesktop = UInt32(0x01)
public let kUsageX = UInt32(0x30)
public let kUsageY = UInt32(0x31)

func warn(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

/// Append a diagnostic line to ~/.config/xeneon-toolbox/touch-debug.log — but only
/// when XENEON_TOUCH_DEBUG is set OR a `touchdebug` marker file exists (so an app
/// launched via `open`, whose stderr is lost, can still be diagnosed).
public func touchDiag(_ s: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/xeneon-toolbox")
    let enabled = ProcessInfo.processInfo.environment["XENEON_TOUCH_DEBUG"] != nil
        || FileManager.default.fileExists(atPath: dir.appendingPathComponent("touchdebug").path)
    guard enabled else { return }
    let url = dir.appendingPathComponent("touch-debug.log")
    let line = Data("[\(Date())] \(s)\n".utf8)
    if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; h.seekToEndOfFile(); h.write(line) }
    else { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try? line.write(to: url) }
}

public func makeManager() -> IOHIDManager {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let match: [String: Any] = [kIOHIDVendorIDKey as String: kVendorID,
                                kIOHIDProductIDKey as String: kProductID]
    IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
    return manager
}

public func matchedDevices(_ manager: IOHIDManager) -> [IOHIDDevice] {
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return Array(set)
}

// The WCH controller exposes several HID interfaces; the digitizer's X/Y
// elements may live on any of them, so scan them all.
public func allElements(_ devices: [IOHIDDevice]) -> [IOHIDElement] {
    devices.flatMap { (IOHIDDeviceCopyMatchingElements($0, nil, 0) as? [IOHIDElement]) ?? [] }
}

public func logicalRange(of elements: [IOHIDElement], page: UInt32, usage: UInt32) -> (Double, Double)? {
    var best: (Double, Double)?
    for e in elements where IOHIDElementGetUsagePage(e) == page && IOHIDElementGetUsage(e) == usage {
        let lo = Double(IOHIDElementGetLogicalMin(e))
        let hi = Double(IOHIDElementGetLogicalMax(e))
        guard hi > lo else { continue }
        if best == nil || (hi - lo) > (best!.1 - best!.0) { best = (lo, hi) }
    }
    return best
}

public func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids
}

/// Resolves the Edge's display rect: a preferred id if given, else the active
/// display matching the panel's 2560x720 geometry.
public func findEdgeDisplay(preferred: CGDirectDisplayID?) -> DisplayRect? {
    if let id = preferred {
        let b = CGDisplayBounds(id)
        return DisplayRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height)
    }
    for id in activeDisplays() {
        let b = CGDisplayBounds(id)
        if abs(b.width - 2560) < 2 && abs(b.height - 720) < 2 {
            return DisplayRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height)
        }
    }
    return nil
}

/// Opens the digitizer. Seizing stops macOS's own cursor handling but macOS
/// usually holds the device exclusively (kIOReturnExclusiveAccess), so on that
/// failure we fall back to a non-exclusive open and inject events alongside it.
public func openManager(preferSeize: Bool) -> (manager: IOHIDManager, seized: Bool)? {
    // Trigger the Input Monitoring prompt / register the app in the list so the
    // user can grant it (otherwise reading the digitizer silently fails).
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    touchDiag("openManager: InputMonitoring=\(access == kIOHIDAccessTypeGranted ? "GRANTED" : access == kIOHIDAccessTypeDenied ? "DENIED" : "UNKNOWN")")
    if preferSeize {
        let manager = makeManager()
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        touchDiag(String(format: "seize open -> 0x%08X (%@)", result, result == kIOReturnSuccess ? "OK" : "fail"))
        if result == kIOReturnSuccess { return (manager, true) }
        if result == kIOReturnExclusiveAccess {
            warn("Note: macOS holds the digitizer exclusively; running non-exclusively (it may also move the cursor).\n")
        } else {
            warn(String(format: "Note: could not seize digitizer (IOReturn 0x%08X); running non-exclusively.\n", result))
        }
    }

    let manager = makeManager()
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    touchDiag(String(format: "non-exclusive open -> 0x%08X (%@)", result, result == kIOReturnSuccess ? "OK" : "fail"))
    guard result == kIOReturnSuccess else {
        warn(String(format: "Failed to open HID manager (IOReturn 0x%08X).\n" +
                            "  • Grant Input Monitoring in System Settings → Privacy & Security.\n", result))
        return nil
    }
    return (manager, false)
}
