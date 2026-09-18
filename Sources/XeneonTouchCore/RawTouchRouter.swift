import Foundation

/// A rectangle of the panel (global screen coordinates) whose touches go to the
/// app as raw fingers instead of driving the pointer.
public struct RawRegion: Equatable, Sendable {
    public let id: Int
    public let x, y, width, height: Double

    public init(id: Int, x: Double, y: Double, width: Double, height: Double) {
        self.id = id; self.x = x; self.y = y; self.width = width; self.height = height
    }

    func contains(_ p: ScreenPoint) -> Bool {
        p.x >= x && p.x < x + width && p.y >= y && p.y < y + height
    }
}

public struct RawTouch: Equatable, Sendable {
    public let id: Int
    public let region: Int
    public let point: ScreenPoint

    public init(id: Int, region: Int, point: ScreenPoint) {
        self.id = id; self.region = region; self.point = point
    }
}

/// Splits each report between the pointer and the raw regions. A finger belongs
/// to whichever side it landed on until it lifts, so a slide that leaves a fader
/// keeps driving the fader and never turns into a stray click.
public struct RawTouchRouter: Sendable {
    public var regions: [RawRegion] = []
    private var owner: [Int: Int?] = [:]   // contact id → region id, or nil for the pointer
    private var reportedRaw = false

    public init() {}

    public var hasRawTouches: Bool { reportedRaw }

    /// `raw` is nil when there is nothing to tell the app; an empty list means the
    /// last raw finger has just lifted.
    public mutating func route(_ contacts: [TouchContact]) -> (pointer: [TouchContact], raw: [RawTouch]?) {
        let live = Set(contacts.map(\.id))
        owner = owner.filter { live.contains($0.key) }

        var pointer: [TouchContact] = [], raw: [RawTouch] = []
        for c in contacts {
            if owner[c.id] == nil { owner[c.id] = .some(regions.first { $0.contains(c.point) }?.id) }
            guard let region = owner[c.id] ?? nil else { pointer.append(c); continue }
            // The region went away mid-touch: the finger is nobody's until it lifts.
            if regions.contains(where: { $0.id == region }) { raw.append(RawTouch(id: c.id, region: region, point: c.point)) }
        }
        defer { reportedRaw = !raw.isEmpty }
        return (pointer, raw.isEmpty && !reportedRaw ? nil : raw)
    }

    /// Forget every finger (device lost, driver stopped). Returns true when the
    /// app still believes raw fingers are down and needs an empty report.
    public mutating func reset() -> Bool {
        defer { owner = [:]; reportedRaw = false }
        return reportedRaw
    }
}
