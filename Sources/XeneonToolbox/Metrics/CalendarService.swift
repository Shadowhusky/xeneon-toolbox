import AppKit
import EventKit
import Foundation

/// The classic always-on-display widget: your current or next calendar event.
/// Reads via EventKit with the user's consent; stays hidden when there's no
/// access or nothing coming up in the next 24 hours.
@MainActor
final class CalendarService: ObservableObject {
    struct NextEvent: Equatable {
        let title: String
        let start: Date
        let isNow: Bool

        var timeLabel: String {
            if isNow { return "Now" }
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return f.string(from: start)
        }
    }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let calendarColorRGB: (Double, Double, Double)
        let isNow: Bool
        let isPast: Bool

        static func == (a: Event, b: Event) -> Bool {
            a.id == b.id && a.isNow == b.isNow && a.isPast == b.isPast
        }

        var timeLabel: String {
            if allDay { return "All day" }
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            return f.string(from: start)
        }
    }

    @Published private(set) var next: NextEvent?
    @Published private(set) var today: [Event] = []
    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        if ProcessInfo.processInfo.environment["XENEON_AGENDA"] != nil { injectMock(); return }
        requestThenRefresh()
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store)
    }

    @objc private func storeChanged(_ note: Notification) {
        Task { @MainActor in refresh() }
    }

    private func requestThenRefresh() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            refresh()
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    AppLog.info("calendar", "access \(granted ? "granted" : "declined")")
                    if granted { self?.refresh() }
                }
            }
        default:
            AppLog.info("calendar", "no calendar access — next-event widget hidden")
        }
    }

    func refresh() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600 * 8),
                                                 end: now.addingTimeInterval(3600 * 24),
                                                 calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        if let current = events.first(where: { $0.startDate <= now && $0.endDate > now }) {
            next = NextEvent(title: current.title ?? "Busy", start: current.startDate, isNow: true)
        } else if let upcoming = events.first(where: { $0.startDate > now }) {
            next = NextEvent(title: upcoming.title ?? "Busy", start: upcoming.startDate, isNow: false)
        } else {
            next = nil
        }

        // Today's schedule (timed + all-day), for the agenda view.
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let todayPred = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        today = store.events(matching: todayPred)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { ev in
                let c = ev.calendar?.cgColor ?? NSColor.systemGray.cgColor
                let rgb = Self.rgb(c)
                return Event(id: ev.eventIdentifier ?? UUID().uuidString,
                             title: ev.title ?? "Busy", start: ev.startDate, end: ev.endDate,
                             allDay: ev.isAllDay, calendarColorRGB: rgb,
                             isNow: !ev.isAllDay && ev.startDate <= now && ev.endDate > now,
                             isPast: !ev.isAllDay && ev.endDate <= now)
            }
    }

    /// Sample schedule for off-screen agenda mockups (XENEON_AGENDA).
    private func injectMock() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int) -> Date { cal.date(byAdding: .init(hour: h, minute: m), to: day)! }
        let now = Date()
        let raw: [(String, Date, Date, Bool, (Double, Double, Double))] = [
            ("Product sync", at(9, 0), at(9, 30), false, (0.20, 0.55, 0.95)),
            ("Design review", at(11, 0), at(12, 0), false, (0.95, 0.45, 0.25)),
            ("Lunch with Sam", at(12, 30), at(13, 30), false, (0.35, 0.75, 0.40)),
            ("Focus block", at(14, 0), at(16, 0), false, (0.62, 0.45, 0.95)),
            ("Ship v1.10", at(17, 0), at(17, 30), false, (0.95, 0.35, 0.55)),
        ]
        today = raw.map {
            Event(id: $0.0, title: $0.0, start: $0.1, end: $0.2, allDay: $0.3,
                  calendarColorRGB: $0.4, isNow: $0.1 <= now && $0.2 > now, isPast: $0.2 <= now)
        }
        next = NextEvent(title: "Focus block", start: at(14, 0), isNow: false)
    }

    private static func rgb(_ color: CGColor) -> (Double, Double, Double) {
        guard let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3 else {
            let c = color.components
            if let c, c.count >= 3 { return (Double(c[0]), Double(c[1]), Double(c[2])) }
            return (0.5, 0.5, 0.5)
        }
        return (Double(c[0]), Double(c[1]), Double(c[2]))
    }
}
