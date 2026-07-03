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

    @Published private(set) var next: NextEvent?
    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
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
    }
}
