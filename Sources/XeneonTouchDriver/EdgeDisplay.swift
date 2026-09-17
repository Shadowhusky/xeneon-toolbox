import Foundation
import CoreGraphics
import XeneonTouchCore

/// The connected Xeneon Edge as macOS currently drives it — whatever mode it is in.
public struct EdgeDisplay: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let bounds: CGRect            // CGDisplayBounds: top-left global coordinates
    public let pointSize: CGSize
    public let pixelSize: CGSize
    public let refreshHz: Double

    public var isNativeMode: Bool {
        EdgeModeChooser.isNative(width: Int(pointSize.width), height: Int(pointSize.height), pixelWidth: Int(pixelSize.width))
    }
    public var modeLabel: String { "\(Int(pointSize.width)) × \(Int(pointSize.height))" }
    public var rect: DisplayRect {
        DisplayRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
    }
}

/// Finds the Edge by identity rather than by geometry, so the kiosk, the touch
/// mapping and the resolution advisor all agree even when macOS has put the panel
/// into a scaled mode. Identity, in order: EDID vendor/model, the display name,
/// and finally a mode list that offers the panel's 2560×720 timing.
public enum EdgeDisplayLocator {
    public static let vendorNumber: UInt32 = 3672
    public static let modelNumber: UInt32 = 60672

    public static func current(nameHint: (CGDirectDisplayID) -> String? = { _ in nil }) -> EdgeDisplay? {
        for id in activeDisplays() where isEdge(id, nameHint: nameHint) { return describe(id) }
        return nil
    }

    public static func isEdge(_ id: CGDirectDisplayID, nameHint: (CGDirectDisplayID) -> String? = { _ in nil }) -> Bool {
        if CGDisplayVendorNumber(id) == vendorNumber && CGDisplayModelNumber(id) == modelNumber { return true }
        if let name = nameHint(id), name.uppercased().contains("XENEON") { return true }
        return probeCache.hasNativeMode(id)
    }

    public static func describe(_ id: CGDirectDisplayID) -> EdgeDisplay {
        let b = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        return EdgeDisplay(
            id: id, bounds: b,
            pointSize: CGSize(width: CGFloat(mode?.width ?? Int(b.width)), height: CGFloat(mode?.height ?? Int(b.height))),
            pixelSize: CGSize(width: CGFloat(mode?.pixelWidth ?? Int(b.width)), height: CGFloat(mode?.pixelHeight ?? Int(b.height))),
            refreshHz: mode?.refreshRate ?? 0)
    }

    /// The mode-list probe walks every mode of a display through the window
    /// server; remember the answer per (id, vendor, model) so non-Edge monitors
    /// with hundreds of modes aren't re-walked on every lookup.
    private final class ProbeCache: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [String: Bool] = [:]
        func hasNativeMode(_ id: CGDirectDisplayID) -> Bool {
            let key = "\(id)/\(CGDisplayVendorNumber(id))/\(CGDisplayModelNumber(id))"
            lock.lock(); defer { lock.unlock() }
            if let hit = results[key] { return hit }
            let has = CGSDisplayModes.all(for: id).contains {
                $0.width == EdgeModeChooser.nativeWidth && $0.height == EdgeModeChooser.nativeHeight
            }
            results[key] = has
            return has
        }
    }
    private static let probeCache = ProbeCache()
}

/// The window server's full mode list. The public `CGDisplayCopyAllDisplayModes`
/// omits the Edge's native 2560×720 timing on some Macs (macOS treats 1920×1080 as
/// the panel's default), so this uses the same private CoreGraphics entry points
/// displayplacer relies on, resolved at runtime and degrading to "unavailable".
public enum CGSDisplayModes {
    private typealias CountFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias DescFn = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> CGError
    private typealias CurrentFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> CGError
    private typealias ConfigureFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> CGError

    private struct Symbols { let count: CountFn; let desc: DescFn; let current: CurrentFn; let configure: ConfigureFn }
    private static let symbols: Symbols? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: T.self) } }
        guard let count = sym("CGSGetNumberOfDisplayModes", CountFn.self),
              let desc = sym("CGSGetDisplayModeDescriptionOfLength", DescFn.self),
              let current = sym("CGSGetCurrentDisplayMode", CurrentFn.self),
              let configure = sym("CGSConfigureDisplayMode", ConfigureFn.self) else { return nil }
        return Symbols(count: count, desc: desc, current: current, configure: configure)
    }()

    // Descriptor layout (0xD4 bytes): mode number @0, flags @4, width @8, height @12, density @0xD0.
    private static let descriptorLength: Int32 = 0xD4

    public static var available: Bool { symbols != nil }

    public static func all(for id: CGDirectDisplayID) -> [DisplayModeCandidate] {
        guard let s = symbols else { return [] }
        var n: Int32 = 0
        guard s.count(id, &n) == .success, n > 0 else { return [] }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(descriptorLength), alignment: 4)
        defer { buf.deallocate() }
        var out: [DisplayModeCandidate] = []
        out.reserveCapacity(Int(n))
        for i in 0..<n {
            guard s.desc(id, i, buf, descriptorLength) == .success else { continue }
            out.append(DisplayModeCandidate(
                number: Int32(bitPattern: buf.load(fromByteOffset: 0, as: UInt32.self)),
                width: Int(buf.load(fromByteOffset: 8, as: UInt32.self)),
                height: Int(buf.load(fromByteOffset: 12, as: UInt32.self)),
                density: Double(buf.load(fromByteOffset: 0xD0, as: Float.self)),
                flags: buf.load(fromByteOffset: 4, as: UInt32.self)))
        }
        return out
    }

    public static func current(for id: CGDirectDisplayID) -> Int32? {
        guard let s = symbols else { return nil }
        var mode: Int32 = -1
        return s.current(id, &mode) == .success ? mode : nil
    }

    /// Switch `id` to mode `number` and persist the choice, exactly like the
    /// Displays settings pane would.
    @discardableResult
    public static func apply(_ number: Int32, to id: CGDirectDisplayID) -> Bool {
        guard let s = symbols else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard s.configure(config, id, number) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
