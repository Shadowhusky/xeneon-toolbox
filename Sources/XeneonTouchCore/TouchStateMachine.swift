import Foundation

/// The lifecycle phase of a scroll gesture. macOS SwiftUI scroll views only
/// respond to *continuous* (trackpad-style) scroll events, which must be framed
/// by a began…changed…ended phase sequence.
public enum ScrollPhase: Equatable, Sendable { case began, changed, ended }

/// A pointer action to inject, derived from the touch contact stream.
public enum PointerAction: Equatable, Sendable {
    /// Move the cursor to the point without pressing (hover / position a tap or
    /// scroll target).
    case move(ScreenPoint)
    /// Press the left button at the point.
    case press(ScreenPoint)
    /// Left button moved while pressed (dragging a control such as a slider).
    case drag(ScreenPoint)
    /// Release the left button at the point.
    case release(ScreenPoint)
    /// Scroll by a finger delta in screen pixels (dx, dy). Positive dy = finger
    /// moved down. The driver turns this into continuous scroll-wheel events so
    /// SwiftUI scroll views — which ignore left-drag on macOS — actually scroll.
    case scroll(dx: Double, dy: Double, phase: ScrollPhase)
    /// Pinch zoom step: the change in the distance between two fingers, in screen
    /// pixels (positive = spreading / zoom in), plus the midpoint between the two
    /// fingers so the driver can anchor the zoom there. The driver turns this into
    /// a Command-modified scroll, which the browser treats as page zoom.
    case zoom(delta: Double, center: ScreenPoint)
}

/// Converts a stream of (contact, point) samples into pointer actions.
///
/// A single contact is classified once it moves past `tapSlop`:
///   • stays put  → a **tap** (click emitted on release)
///   • moves mostly vertically → a **scroll** (scroll-wheel deltas, no click)
///   • moves mostly horizontally → a **drag** (press + drag, for sliders etc.)
///
/// The press is deferred until the gesture is known, so starting to scroll on
/// top of a button never fires that button. Single contact only.
public struct TouchStateMachine: Sendable {
    private enum Phase { case idle, pending, scrolling, dragging }
    private var phase: Phase = .idle
    private var start: ScreenPoint?
    private var last: ScreenPoint?
    private let tapSlop: Double

    /// `tapSlop` is the movement (in screen px) tolerated before a contact stops
    /// counting as a tap and is classified as a scroll or drag.
    public init(tapSlop: Double = 10) {
        self.tapSlop = tapSlop
    }

    /// Feed one digitizer sample. `point` is the mapped screen position, or nil
    /// when the report carried no usable coordinates.
    public mutating func update(contact: Bool, point: ScreenPoint?) -> [PointerAction] {
        guard contact else { return end(at: point) }

        guard let p = point ?? last else { return [] }

        switch phase {
        case .idle:
            phase = .pending
            start = p; last = p
            return [.move(p)]

        case .pending:
            let s = start ?? p
            let dx = p.x - s.x, dy = p.y - s.y
            if max(abs(dx), abs(dy)) < tapSlop {
                guard p != last else { return [] }
                last = p
                return [.move(p)]
            }
            let prev = last ?? s
            // Bias toward scrolling — only a clearly-horizontal drag grabs a
            // control (e.g. the brightness slider); everything else scrolls.
            if abs(dx) > abs(dy) * 1.4 {
                phase = .dragging
                last = p
                return [.press(s), .drag(p)]
            } else {
                phase = .scrolling
                last = p
                return [.scroll(dx: 0, dy: 0, phase: .began),
                        .scroll(dx: p.x - prev.x, dy: p.y - prev.y, phase: .changed)]
            }

        case .scrolling:
            let prev = last ?? p
            guard p != prev else { return [] }
            last = p
            return [.scroll(dx: p.x - prev.x, dy: p.y - prev.y, phase: .changed)]

        case .dragging:
            guard p != last else { return [] }
            last = p
            return [.drag(p)]
        }
    }

    private mutating func end(at point: ScreenPoint?) -> [PointerAction] {
        let p = point ?? last
        let phase = self.phase
        self.phase = .idle
        self.start = nil
        switch phase {
        case .idle:
            return []
        case .scrolling:
            return [.scroll(dx: 0, dy: 0, phase: .ended)]   // close the gesture
        case .pending:
            guard let p else { return [] }
            last = p
            return [.press(p), .release(p)]   // tap → click
        case .dragging:
            guard let p else { return [] }
            last = p
            return [.release(p)]
        }
    }

    /// Force the contact to end (e.g. the device was unplugged mid-touch) so a
    /// held button doesn't get stuck down or a scroll gesture left open.
    public mutating func reset() -> [PointerAction] {
        let ending = phase
        let p = last
        phase = .idle
        start = nil
        switch ending {
        case .dragging: if let p { return [.release(p)] }
        case .scrolling: return [.scroll(dx: 0, dy: 0, phase: .ended)]
        default: break
        }
        return []
    }
}
