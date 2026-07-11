import Foundation

/// Detects a stationary single-finger long-press (the deck's "open on which
/// screen" menu). Pure and clock-free — the caller passes the current time — so
/// the tap/hold/release logic is unit-testable.
///
/// The subtle rule this encodes: once a press has **engaged**, it keeps owning
/// its contact until the finger physically lifts — even if detection is disabled
/// mid-gesture. The app disables detection the instant the menu appears (so no
/// second press can start under it), but the finger that opened the menu is
/// still down. Without this ownership the still-down contact would be handed
/// back to the normal pointer pipeline and its release would fire a tap that
/// immediately dismisses the menu.
public struct LongPressDetector: Sendable {
    /// What the caller should do with the current frame.
    public enum Outcome: Equatable, Sendable {
        /// Not engaged — process the frame normally (pointer pipeline).
        case none
        /// Owned by an engaged press — drop the frame (emit no pointer events).
        case swallow
        /// Just crossed the threshold — fire the long-press at this point, then
        /// swallow. Emitted exactly once per press.
        case fire(ScreenPoint)
    }

    private var start: ScreenPoint?
    private var startTime = 0.0
    private var active = false
    private let duration: Double
    private let slop: Double

    public init(duration: Double = 0.5, slop: Double = 16) {
        self.duration = duration
        self.slop = slop
    }

    /// Feed one frame. `count` is the number of contacts, `point` the primary
    /// contact's screen position (nil when none), `now` a monotonic timestamp.
    public mutating func update(enabled: Bool, count: Int, point: ScreenPoint?, now: Double) -> Outcome {
        // An engaged press survives detection being switched off mid-gesture.
        guard enabled || active else { start = nil; active = false; return .none }

        // Lift or a second finger ends the press. Swallow the ending frame of an
        // engaged press so its release can't land as a tap; otherwise pass it
        // through (a normal short tap the pointer pipeline should handle).
        guard count == 1, let p = point else {
            let wasActive = active
            start = nil; active = false
            return wasActive ? .swallow : .none
        }

        if active { return .swallow }
        guard let s = start else { start = p; startTime = now; return .none }
        if hypot(p.x - s.x, p.y - s.y) > slop { start = nil; return .none }   // moved → not a press
        if now - startTime >= duration {
            active = true
            return .fire(s)
        }
        return .none
    }

    /// Abandon any in-progress or engaged press (device lost, gesture cancelled).
    public mutating func reset() {
        start = nil
        active = false
    }
}
