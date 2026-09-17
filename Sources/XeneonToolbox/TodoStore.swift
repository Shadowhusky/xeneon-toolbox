import Foundation
import UserNotifications
import ToolboxKit

/// Owns the to-do / reminder list: persists to disk and schedules OS
/// notifications for items with a due date (so reminders fire even when the
/// user is in another tab or app). Shared by the Tasks UI and the assistant.
@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []

    private static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox/todos.json")
    }

    init() {
        if ProcessInfo.processInfo.environment["XENEON_TODOS_DEMO"] != nil { items = Self.demo; return }
        load()
    }

    /// Sample items for off-screen mockups (never saved unless edited).
    private static var demo: [TodoItem] {
        let now = Date()
        return [TodoItem(title: "Send the invoice to Acme", dueAt: now.addingTimeInterval(-3600)),
                TodoItem(title: "Review pull request #128", dueAt: now.addingTimeInterval(2.5 * 3600)),
                TodoItem(title: "Water the plants"),
                TodoItem(title: "Book dentist appointment", dueAt: now.addingTimeInterval(26 * 3600))]
    }

    // UNUserNotificationCenter aborts the process unless we're a real bundle
    // (it's nil for the bare CLI binary). Gate all notification use on this.
    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            // On first launch, scheduling before the permission sheet completes can
            // silently drop every existing reminder. Re-sync only after permission
            // is known, and return to the store's main-actor isolation.
            Task { @MainActor in
                guard let self else { return }
                for item in self.items where item.dueAt != nil && !item.done { self.schedule(item) }
            }
        }
    }

    /// Sorted for display: open items first (by due date then created), done last.
    var sorted: [TodoItem] {
        items.sorted { a, b in
            if a.done != b.done { return !a.done }
            switch (a.dueAt, b.dueAt) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    @discardableResult
    func add(_ title: String, dueAt: Date? = nil, recurrence: Recurrence = .none) -> TodoItem {
        let item = TodoItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), dueAt: dueAt, recurrence: recurrence)
        items.append(item)
        save()
        if dueAt != nil { schedule(item) }
        return item
    }

    enum ToggleResult { case completed, reopened, rolledForward(Date), notFound }

    @discardableResult
    func toggle(_ id: UUID) -> ToggleResult {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return .notFound }
        // Completing a recurring reminder rolls it forward instead of marking done.
        if !items[i].done, items[i].recurrence != .none, items[i].dueAt != nil {
            cancel(id)
            items[i] = items[i].advanced()
            save()
            schedule(items[i])
            return .rolledForward(items[i].dueAt ?? Date())
        }
        items[i].done.toggle()
        save()
        if items[i].done { cancel(id) }
        else if items[i].dueAt != nil { schedule(items[i]) }
        return items[i].done ? .completed : .reopened
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
        cancel(id)
    }

    func update(_ id: UUID, title: String? = nil, dueAt: Date?? = nil, recurrence: Recurrence? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if let t = title { items[i].title = t }
        if let d = dueAt { items[i].dueAt = d }
        if let r = recurrence { items[i].recurrence = r }
        save()
        cancel(id)
        if !items[i].done, items[i].dueAt != nil { schedule(items[i]) }
    }

    func clearCompleted() {
        for done in items where done.done { cancel(done.id) }
        items.removeAll { $0.done }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: Self.storeURL) }
    }

    // MARK: - Notifications

    private func schedule(_ item: TodoItem) {
        guard notificationsAvailable, let due = item.dueAt, due > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = item.title
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func cancel(_ id: UUID) {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
