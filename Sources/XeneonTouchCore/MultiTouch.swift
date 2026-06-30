import Foundation

/// One finger as reported by the digitizer, in raw device coordinates.
public struct RawContact: Equatable, Sendable {
    public let id: Int
    public let x: Int
    public let y: Int
    public init(id: Int, x: Int, y: Int) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// One active finger, already mapped onto the screen.
public struct TouchContact: Equatable, Sendable {
    public let id: Int
    public let point: ScreenPoint
    public init(id: Int, point: ScreenPoint) {
        self.id = id
        self.point = point
    }
}

/// Parses the Xeneon Edge's Windows-Precision touch input reports (report id
/// `0x0D`). Each report carries ten finger records — a status byte (bit 0 = tip
/// switch, bits 4-7 = contact id) followed by little-endian u16 X and Y — then a
/// 16-bit scan time and an 8-bit contact count. Only fingers whose tip switch is
/// set are touching, so those are the ones returned.
public enum DigitizerReport {
    public static let reportID: UInt8 = 0x0D
    static let fingerStride = 5      // status(1) + x(2) + y(2)
    static let maxFingers = 10

    /// `payload` is the report body **without** the leading report-id byte.
    public static func parse(payload: [UInt8]) -> [RawContact] {
        var out: [RawContact] = []
        out.reserveCapacity(maxFingers)
        for i in 0..<maxFingers {
            let off = i * fingerStride
            guard off + fingerStride <= payload.count else { break }
            let status = payload[off]
            guard status & 0x01 != 0 else { continue }   // tip switch down?
            let id = Int((status >> 4) & 0x0F)
            let x = Int(payload[off + 1]) | (Int(payload[off + 2]) << 8)
            let y = Int(payload[off + 3]) | (Int(payload[off + 4]) << 8)
            out.append(RawContact(id: id, x: x, y: y))
        }
        return out
    }
}

/// 1€ filter — smooths pointer jitter with very little lag. Low cutoff kills
/// noise while a finger rests; the cutoff rises with speed so fast moves stay
/// responsive. One instance per axis. See Casiez et al., CHI 2012.
public struct OneEuroFilter: Sendable {
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double
    private var xPrev: Double?
    private var dxPrev = 0.0

    public init(minCutoff: Double = 1.7, beta: Double = 0.02, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    public mutating func filter(_ x: Double, dt: Double) -> Double {
        guard dt > 0, let xp = xPrev else { xPrev = x; return x }
        let dx = (x - xp) / dt
        let aD = alpha(cutoff: dCutoff, dt: dt)
        let dxHat = aD * dx + (1 - aD) * dxPrev
        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(cutoff: cutoff, dt: dt)
        let xHat = a * x + (1 - a) * xp
        xPrev = xHat
        dxPrev = dxHat
        return xHat
    }

    public mutating func reset() {
        xPrev = nil
        dxPrev = 0
    }
}

/// Turns a stream of multi-finger samples into pointer actions.
///
/// One finger is delegated to the proven single-contact `TouchStateMachine`
/// (tap / scroll / drag). Two fingers are a deliberate gesture: once they move
/// past `moveThreshold` the recognizer locks them into either a **pan**
/// (two-finger scroll) or a **pinch** (zoom) for the rest of the gesture, so it
/// never flip-flops. A gesture stays "multi" until *every* finger lifts, so a
/// stray finger leaving mid-pinch can't suddenly turn it into a drag.
public struct MultiTouchRecognizer: Sendable {
    private enum Mode: Sendable { case idle, single, multi, drain }
    private enum Kind: Sendable { case undecided, pan, zoom }

    private var mode: Mode = .idle
    private var kind: Kind = .undecided
    private var single = TouchStateMachine()
    private var lockedPair: (Int, Int)?    // the two contact ids the gesture is tracking
    private var startCentroid = ScreenPoint(x: 0, y: 0)
    private var lastCentroid = ScreenPoint(x: 0, y: 0)
    private var startSpread = 0.0
    private var lastSpread = 0.0
    private let moveThreshold: Double

    public init(moveThreshold: Double = 12) {
        self.moveThreshold = moveThreshold
    }

    public mutating func update(contacts: [TouchContact]) -> [PointerAction] {
        let n = contacts.count
        switch mode {
        case .idle:
            if n == 0 { return [] }
            if n == 1 { mode = .single; return single.update(contact: true, point: contacts[0].point) }
            mode = .multi; beginMulti(contacts); return []

        case .single:
            if n == 0 { mode = .idle; return single.update(contact: false, point: nil) }
            if n == 1 { return single.update(contact: true, point: contacts[0].point) }
            // A second finger arrived: abandon the single-finger gesture (no click)
            // and switch to a two-finger gesture.
            let out = single.reset()
            mode = .multi; beginMulti(contacts)
            return out

        case .multi:
            if n >= 2 { return updateMulti(contacts) }
            let out = endMulti()
            mode = (n == 0) ? .idle : .drain
            return out

        case .drain:
            // Fingers still down after a two-finger gesture ended — wait for a
            // clean release so leftover fingers don't start a stray drag.
            if n == 0 { mode = .idle }
            return []
        }
    }

    /// Force any in-flight gesture to end cleanly (device unplugged, watchdog
    /// timeout) so a held button or open scroll can't get stuck.
    public mutating func reset() -> [PointerAction] {
        let out: [PointerAction]
        switch mode {
        case .single: out = single.reset()
        case .multi: out = endMulti()
        default: out = []
        }
        mode = .idle
        kind = .undecided
        lockedPair = nil
        return out
    }

    // MARK: - Two-finger handling

    private mutating func beginMulti(_ contacts: [TouchContact]) {
        let (a, b) = primaryTwo(contacts)
        lockedPair = (a.id, b.id)
        startCentroid = midpoint(a, b); lastCentroid = startCentroid
        startSpread = spread(a, b); lastSpread = startSpread
        kind = .undecided
    }

    private mutating func updateMulti(_ contacts: [TouchContact]) -> [PointerAction] {
        guard let (a, b, reseeded) = workingPair(contacts) else { return [] }
        let centroid = midpoint(a, b)
        let spr = spread(a, b)
        // The tracked pair changed (a finger lifted, or a new finger took a lower
        // id). Re-anchor to the new pair and emit nothing this frame, so we never
        // difference one physical pair's position against another's.
        if reseeded {
            startCentroid = centroid; lastCentroid = centroid
            startSpread = spr; lastSpread = spr
            return []
        }

        switch kind {
        case .undecided:
            let movedCentroid = hypot(centroid.x - startCentroid.x, centroid.y - startCentroid.y)
            let movedSpread = abs(spr - startSpread)
            guard max(movedCentroid, movedSpread) >= moveThreshold else {
                lastCentroid = centroid; lastSpread = spr
                return []
            }
            if movedSpread > movedCentroid {
                kind = .zoom; lastSpread = spr
                return [.zoom(delta: spr - startSpread, center: centroid)]
            } else {
                kind = .pan
                let dx = centroid.x - lastCentroid.x, dy = centroid.y - lastCentroid.y
                lastCentroid = centroid
                return [.scroll(dx: 0, dy: 0, phase: .began),
                        .scroll(dx: dx, dy: dy, phase: .changed)]
            }

        case .pan:
            let dx = centroid.x - lastCentroid.x, dy = centroid.y - lastCentroid.y
            guard dx != 0 || dy != 0 else { return [] }
            lastCentroid = centroid
            return [.scroll(dx: dx, dy: dy, phase: .changed)]

        case .zoom:
            let d = spr - lastSpread
            guard d != 0 else { return [] }
            lastSpread = spr
            return [.zoom(delta: d, center: centroid)]
        }
    }

    private mutating func endMulti() -> [PointerAction] {
        defer { kind = .undecided; lockedPair = nil }
        return kind == .pan ? [.scroll(dx: 0, dy: 0, phase: .ended)] : []
    }

    /// Resolve the pair the gesture is tracking. Prefer the locked pair while both
    /// of its fingers are still down; otherwise re-pick the two lowest ids and flag
    /// a re-seed so the caller re-anchors instead of jumping.
    private mutating func workingPair(_ contacts: [TouchContact]) -> (TouchContact, TouchContact, Bool)? {
        guard contacts.count >= 2 else { return nil }
        if let (id0, id1) = lockedPair,
           let a = contacts.first(where: { $0.id == id0 }),
           let b = contacts.first(where: { $0.id == id1 }) {
            return (a, b, false)
        }
        let (a, b) = primaryTwo(contacts)
        lockedPair = (a.id, b.id)
        return (a, b, true)
    }

    /// The two lowest-id contacts.
    private func primaryTwo(_ contacts: [TouchContact]) -> (TouchContact, TouchContact) {
        let sorted = contacts.sorted { $0.id < $1.id }
        return (sorted[0], sorted[1])
    }

    private func midpoint(_ a: TouchContact, _ b: TouchContact) -> ScreenPoint {
        ScreenPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
    }

    private func spread(_ a: TouchContact, _ b: TouchContact) -> Double {
        hypot(a.point.x - b.point.x, a.point.y - b.point.y)
    }
}
