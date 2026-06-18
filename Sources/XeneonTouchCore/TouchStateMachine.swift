import Foundation

/// A pointer action to inject, derived from the touch contact stream.
public enum PointerAction: Equatable, Sendable {
    /// Contact began: move the cursor to the point, then press the left button.
    case moveAndPress(ScreenPoint)
    /// Contact moved while pressed.
    case drag(ScreenPoint)
    /// Contact ended at the last known point.
    case release(ScreenPoint)
}

/// Converts a stream of (contact, point) samples into press/drag/release
/// actions implementing absolute tap-and-drag. Single contact only.
public struct TouchStateMachine: Sendable {
    private var isDown = false
    private var lastPoint: ScreenPoint?

    public init() {}

    /// Feed one digitizer sample. `point` is the mapped screen position, or nil
    /// when the report carried no usable coordinates.
    public mutating func update(contact: Bool, point: ScreenPoint?) -> [PointerAction] {
        guard contact else {
            guard isDown else { return [] }
            isDown = false
            if let p = point { lastPoint = p }
            guard let p = lastPoint else { return [] }
            return [.release(p)]
        }

        guard let p = point ?? lastPoint else { return [] }

        if !isDown {
            isDown = true
            lastPoint = p
            return [.moveAndPress(p)]
        }

        if lastPoint == p { return [] }
        lastPoint = p
        return [.drag(p)]
    }

    /// Force the contact to end (e.g. the device was unplugged mid-touch) so a
    /// held button doesn't get stuck down.
    public mutating func reset() -> [PointerAction] {
        guard isDown, let p = lastPoint else { return [] }
        isDown = false
        return [.release(p)]
    }
}
