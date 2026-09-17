import Foundation

/// One entry of a display's mode list, as reported by the window server.
public struct DisplayModeCandidate: Equatable, Sendable {
    public let number: Int32
    public let width: Int
    public let height: Int
    public let density: Double      // 1 = points equal pixels, 2 = HiDPI
    public let flags: UInt32

    public init(number: Int32, width: Int, height: Int, density: Double, flags: UInt32) {
        self.number = number
        self.width = width
        self.height = height
        self.density = density
        self.flags = flags
    }

    /// kDisplayModeSafeFlag — macOS considers the mode safe to switch to.
    public var isSafe: Bool { flags & 0x2 != 0 }
    public var label: String { "\(width) × \(height)" }
}

/// Picks the Edge's native mode out of a mode list. The panel is 2560×720; any
/// other mode is scaled by the panel and misshapes the Toolbox.
public enum EdgeModeChooser {
    public static let nativeWidth = 2560
    public static let nativeHeight = 720

    /// The 2560×720 @1× mode to recommend: safe-flagged first, then the lowest
    /// mode number. Nil when the list has no native mode (manual path only).
    public static func best(from modes: [DisplayModeCandidate]) -> DisplayModeCandidate? {
        modes
            .filter { $0.width == nativeWidth && $0.height == nativeHeight && abs($0.density - 1) < 0.01 }
            .sorted { ($0.isSafe ? 0 : 1, $0.number) < ($1.isSafe ? 0 : 1, $1.number) }
            .first
    }

    public static func isNative(width: Int, height: Int, pixelWidth: Int) -> Bool {
        width == nativeWidth && height == nativeHeight && pixelWidth == nativeWidth
    }
}
