import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

/// CLI-facing diagnostics that don't inject events — used to confirm the device
/// is present and to read its HID usages/ranges.
public enum Diagnostics {
    final class Printer {
        func handle(value: IOHIDValue) {
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let intVal = IOHIDValueGetIntegerValue(value)
            let lo = IOHIDElementGetLogicalMin(element)
            let hi = IOHIDElementGetLogicalMax(element)
            print(String(format: "page=0x%02X usage=0x%02X value=%ld range=[%ld...%ld]",
                         page, usage, intVal, lo, hi))
        }
    }

    static let printCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<Printer>.fromOpaque(context).takeUnretainedValue().handle(value: value)
    }

    /// Opens non-exclusively, prints X/Y ranges, then streams live reports.
    public static func run() {
        guard let (manager, _) = openManager(preferSeize: false) else { exit(1) }
        let devices = matchedDevices(manager)
        if devices.isEmpty {
            print("No Xeneon Edge digitizer (0x27c0:0x0859) found. Is it connected over USB-C?")
        } else {
            print("Found \(devices.count) matching device(s). Touch the panel to see reports; Ctrl-C to stop.\n")
            let elements = allElements(devices)
            if let x = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageX) {
                print(String(format: "X range:   %.0f...%.0f", x.0, x.1))
            }
            if let y = logicalRange(of: elements, page: kPageGenericDesktop, usage: kUsageY) {
                print(String(format: "Y range:   %.0f...%.0f", y.0, y.1))
            }
        }
        let printer = Printer()
        IOHIDManagerRegisterInputValueCallback(manager, printCallback, Unmanaged.passUnretained(printer).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRun()
    }

    public static func listDisplays() {
        for id in activeDisplays() {
            let b = CGDisplayBounds(id)
            let main = CGDisplayIsMain(id) != 0 ? " (main)" : ""
            print(String(format: "display %u: origin=(%.0f,%.0f) size=%.0fx%.0f%@",
                         id, b.origin.x, b.origin.y, b.width, b.height, main))
        }
    }
}
