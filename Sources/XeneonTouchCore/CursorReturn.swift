import Foundation

/// Sends the pointer back to where it was before a finger landed on the Edge.
/// A tap on the strip must not strand the cursor there while the user is working
/// on another display. Pure state; the driver feeds it and posts the move.
public struct CursorReturn: Sendable {
    public private(set) var home: ScreenPoint?
    private var postedAnything = false
    private var cancelled = false

    public init() {}

    /// A finger has landed. Remembers the pointer unless a return from an earlier
    /// gesture is still owed (momentum was still coasting when this one started).
    public mutating func touchBegan(pointerAt point: ScreenPoint?) {
        guard home == nil else { return }
        home = point
        postedAnything = false
        cancelled = false
    }

    /// The driver placed the pointer (a click, drag or scroll route).
    public mutating func posted() {
        if home != nil { postedAnything = true }
    }

    /// A real mouse or trackpad moved mid-gesture: the user owns the pointer now.
    public mutating func realPointerMoved() {
        if home != nil { cancelled = true }
    }

    /// The gesture and any coasting are over. Where to put the pointer, or nil to
    /// leave it alone (nothing was posted, or the user moved it). Resets.
    public mutating func destination() -> ScreenPoint? {
        defer { home = nil; postedAnything = false; cancelled = false }
        guard let home, postedAnything, !cancelled else { return nil }
        return home
    }
}
