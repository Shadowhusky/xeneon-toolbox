import Foundation

/// Pure countdown state for the focus/pomodoro timer. Clock-free — the owner
/// calls `tick()` once a second — so the start/pause/complete logic is fully
/// unit-testable. The observable `FocusTimer` in the app wraps this and drives it
/// from a real timer, which is why the state lives in the model (not a view) and
/// keeps counting across tab switches.
public struct FocusTimerState: Equatable, Sendable {
    public private(set) var total: Int      // seconds for a full session
    public private(set) var remaining: Int  // seconds left
    public private(set) var running: Bool

    public init(minutes: Int = 25) {
        total = max(1, minutes) * 60
        remaining = total
        running = false
    }

    /// 0 at the start of a session, 1 when finished.
    public var fraction: Double { total == 0 ? 0 : Double(total - remaining) / Double(total) }

    /// "MM:SS" for display.
    public var clock: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    public var finished: Bool { remaining == 0 }

    /// Advance one second. Returns true on the single tick that reaches zero, so
    /// the owner can fire the completion alert exactly once.
    @discardableResult
    public mutating func tick() -> Bool {
        guard running, remaining > 0 else { return false }
        remaining -= 1
        if remaining == 0 { running = false; return true }
        return false
    }

    /// Pick a new session length; resets the countdown and stops.
    public mutating func setDuration(minutes: Int) {
        total = max(1, minutes) * 60
        remaining = total
        running = false
    }

    /// Start or pause. Starting a finished timer rewinds it to a full session.
    public mutating func toggle() {
        if remaining == 0 { remaining = total }
        running.toggle()
    }

    /// Stop and rewind to a full session.
    public mutating func reset() {
        running = false
        remaining = total
    }
}
