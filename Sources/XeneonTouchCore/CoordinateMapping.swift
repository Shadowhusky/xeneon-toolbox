import Foundation

/// A point in macOS global display coordinates (origin top-left of the primary display).
public struct ScreenPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The global bounds of a display, as reported by CoreGraphics.
public struct DisplayRect: Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Maps raw digitizer coordinates onto a display. Logical ranges come from the
/// device's HID elements at runtime; orientation flags are set during calibration.
public struct AxisCalibration: Sendable {
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let maxY: Double
    public var flipX: Bool
    public var flipY: Bool
    public var swapXY: Bool

    public init(
        minX: Double, maxX: Double, minY: Double, maxY: Double,
        flipX: Bool = false, flipY: Bool = false, swapXY: Bool = false
    ) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.flipX = flipX
        self.flipY = flipY
        self.swapXY = swapXY
    }
}

public enum CoordinateMapper {
    /// Map a raw digitizer (x, y) reading to a point on `display`.
    ///
    /// Pipeline: normalize to 0...1 using the logical range, clamp, optionally
    /// swap axes, optionally flip each axis, then scale into the display rect.
    public static func mapToScreen(
        rawX: Double, rawY: Double,
        calibration: AxisCalibration,
        display: DisplayRect
    ) -> ScreenPoint {
        var nx = normalize(rawX, min: calibration.minX, max: calibration.maxX)
        var ny = normalize(rawY, min: calibration.minY, max: calibration.maxY)

        if calibration.swapXY { swap(&nx, &ny) }
        if calibration.flipX { nx = 1 - nx }
        if calibration.flipY { ny = 1 - ny }

        return ScreenPoint(
            x: display.x + nx * display.width,
            y: display.y + ny * display.height
        )
    }

    /// Normalize `value` into 0...1 across [min, max], clamped. A degenerate
    /// range (min == max) maps to 0.
    private static func normalize(_ value: Double, min: Double, max: Double) -> Double {
        let span = max - min
        guard span != 0 else { return 0 }
        let t = (value - min) / span
        return Swift.min(1, Swift.max(0, t))
    }
}
