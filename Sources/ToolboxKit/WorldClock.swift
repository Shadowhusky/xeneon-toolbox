import Foundation

/// One city on the world clock: a display name and an IANA time-zone id.
public struct WorldClock: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var timeZoneID: String

    public init(id: UUID = UUID(), name: String, timeZoneID: String) {
        self.id = id
        self.name = name
        self.timeZoneID = timeZoneID
    }

    public var timeZone: TimeZone? { TimeZone(identifier: timeZoneID) }
}

/// Pure time helpers for rendering a world-clock row, kept out of the views so
/// they can be unit-tested.
public enum WorldClockInfo {
    /// Whole/half-hour offset of `tz` from the local zone, as a short label:
    /// "same", "+8h", "-3h", "+5:30".
    public static func offsetLabel(of tz: TimeZone, from reference: TimeZone = .current, at date: Date) -> String {
        let secs = tz.secondsFromGMT(for: date) - reference.secondsFromGMT(for: date)
        if secs == 0 { return "same" }
        let sign = secs > 0 ? "+" : "-"
        let mins = abs(secs) / 60
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h):\(String(format: "%02d", m))"
    }

    /// Roughly daytime at the zone (06:00–18:00 local). Drives the sun/moon cue.
    public static func isDaytime(in tz: TimeZone, at date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let h = cal.component(.hour, from: date)
        return h >= 6 && h < 18
    }

    /// Calendar-day difference vs the local zone: 0 same day, +1 tomorrow there,
    /// -1 yesterday there.
    public static func dayDelta(of tz: TimeZone, from reference: TimeZone = .current, at date: Date) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        func localMidnight(_ zone: TimeZone) -> Date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        }
        return utc.dateComponents([.day], from: localMidnight(reference), to: localMidnight(tz)).day ?? 0
    }

    /// Short relative-day word, or nil when it's the same day locally.
    public static func dayLabel(of tz: TimeZone, from reference: TimeZone = .current, at date: Date) -> String? {
        switch dayDelta(of: tz, from: reference, at: date) {
        case 0: return nil
        case let d where d > 0: return "Tomorrow"
        default: return "Yesterday"
        }
    }
}

/// A curated set of major cities for the "add city" picker. Friendly name first,
/// IANA identifier second. Browsable by scroll and narrowed by search.
public enum WorldCityCatalog {
    public static let all: [WorldClock] = [
        ("Honolulu", "Pacific/Honolulu"),
        ("Anchorage", "America/Anchorage"),
        ("Los Angeles", "America/Los_Angeles"),
        ("San Francisco", "America/Los_Angeles"),
        ("Vancouver", "America/Vancouver"),
        ("Denver", "America/Denver"),
        ("Phoenix", "America/Phoenix"),
        ("Chicago", "America/Chicago"),
        ("Mexico City", "America/Mexico_City"),
        ("New York", "America/New_York"),
        ("Toronto", "America/Toronto"),
        ("Miami", "America/New_York"),
        ("Bogotá", "America/Bogota"),
        ("Lima", "America/Lima"),
        ("Santiago", "America/Santiago"),
        ("Caracas", "America/Caracas"),
        ("São Paulo", "America/Sao_Paulo"),
        ("Buenos Aires", "America/Argentina/Buenos_Aires"),
        ("Reykjavík", "Atlantic/Reykjavik"),
        ("Lisbon", "Europe/Lisbon"),
        ("London", "Europe/London"),
        ("Dublin", "Europe/Dublin"),
        ("Madrid", "Europe/Madrid"),
        ("Paris", "Europe/Paris"),
        ("Amsterdam", "Europe/Amsterdam"),
        ("Brussels", "Europe/Brussels"),
        ("Zurich", "Europe/Zurich"),
        ("Berlin", "Europe/Berlin"),
        ("Rome", "Europe/Rome"),
        ("Vienna", "Europe/Vienna"),
        ("Stockholm", "Europe/Stockholm"),
        ("Oslo", "Europe/Oslo"),
        ("Copenhagen", "Europe/Copenhagen"),
        ("Warsaw", "Europe/Warsaw"),
        ("Athens", "Europe/Athens"),
        ("Helsinki", "Europe/Helsinki"),
        ("Istanbul", "Europe/Istanbul"),
        ("Kyiv", "Europe/Kyiv"),
        ("Moscow", "Europe/Moscow"),
        ("Cairo", "Africa/Cairo"),
        ("Lagos", "Africa/Lagos"),
        ("Johannesburg", "Africa/Johannesburg"),
        ("Nairobi", "Africa/Nairobi"),
        ("Tel Aviv", "Asia/Jerusalem"),
        ("Riyadh", "Asia/Riyadh"),
        ("Dubai", "Asia/Dubai"),
        ("Tehran", "Asia/Tehran"),
        ("Karachi", "Asia/Karachi"),
        ("Mumbai", "Asia/Kolkata"),
        ("Bengaluru", "Asia/Kolkata"),
        ("Delhi", "Asia/Kolkata"),
        ("Colombo", "Asia/Colombo"),
        ("Dhaka", "Asia/Dhaka"),
        ("Bangkok", "Asia/Bangkok"),
        ("Jakarta", "Asia/Jakarta"),
        ("Singapore", "Asia/Singapore"),
        ("Kuala Lumpur", "Asia/Kuala_Lumpur"),
        ("Hong Kong", "Asia/Hong_Kong"),
        ("Shanghai", "Asia/Shanghai"),
        ("Beijing", "Asia/Shanghai"),
        ("Taipei", "Asia/Taipei"),
        ("Manila", "Asia/Manila"),
        ("Seoul", "Asia/Seoul"),
        ("Tokyo", "Asia/Tokyo"),
        ("Osaka", "Asia/Tokyo"),
        ("Perth", "Australia/Perth"),
        ("Adelaide", "Australia/Adelaide"),
        ("Brisbane", "Australia/Brisbane"),
        ("Sydney", "Australia/Sydney"),
        ("Melbourne", "Australia/Melbourne"),
        ("Auckland", "Pacific/Auckland"),
        ("Fiji", "Pacific/Fiji"),
    ].map { WorldClock(name: $0.0, timeZoneID: $0.1) }

    /// Catalog entries matching a search query (by city name); empty query → all.
    public static func search(_ query: String) -> [WorldClock] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) }
    }

    /// Best-effort resolve a free-text city name to a catalog entry (for the agent).
    public static func resolve(_ name: String) -> WorldClock? {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        if let exact = all.first(where: { $0.name.lowercased() == q }) { return exact }
        if let partial = all.first(where: { $0.name.lowercased().contains(q) }) { return partial }
        if TimeZone(identifier: name) != nil { return WorldClock(name: name, timeZoneID: name) }
        return nil
    }
}
