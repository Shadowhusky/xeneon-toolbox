import Foundation

public enum Recurrence: String, Codable, Sendable, CaseIterable {
    case none, daily, weekly
    public var label: String { self == .none ? "" : rawValue }
}

/// A to-do / reminder item. `dueAt` set ⇒ it's a reminder (fires a notification);
/// `recurrence` ≠ none ⇒ completing it rolls forward to the next occurrence.
public struct TodoItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var createdAt: Date
    public var dueAt: Date?
    public var recurrence: Recurrence

    public init(id: UUID = UUID(), title: String, done: Bool = false,
                createdAt: Date = Date(), dueAt: Date? = nil, recurrence: Recurrence = .none) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.recurrence = recurrence
    }

    // Recurrence is optional in older saved data.
    private enum CodingKeys: String, CodingKey { case id, title, done, createdAt, dueAt, recurrence }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        done = try c.decode(Bool.self, forKey: .done)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
    }

    public var isOverdue: Bool {
        guard !done, let d = dueAt else { return false }
        return d < Date()
    }

    /// Same item rolled to its next occurrence (one step past the current due,
    /// skipping any occurrences already in the past), reset to not-done.
    public func advanced(now: Date = Date()) -> TodoItem {
        guard recurrence != .none, let due = dueAt else { return self }
        let cal = Calendar.current
        let comp: Calendar.Component = recurrence == .daily ? .day : .weekOfYear
        let fallback: TimeInterval = recurrence == .daily ? 86_400 : 604_800
        var next = cal.date(byAdding: comp, value: 1, to: due) ?? due.addingTimeInterval(fallback)
        while next <= now { next = cal.date(byAdding: comp, value: 1, to: next) ?? next.addingTimeInterval(fallback) }
        var copy = self
        copy.dueAt = next
        copy.done = false
        return copy
    }
}

/// Resolve a loose reference from the agent (a 1-based index, or a title
/// substring) to an item — so the model can say "complete buy milk" or
/// "delete 2" without knowing UUIDs. Open items are preferred over done ones.
public enum TodoMatch {
    public static func resolve(_ ref: String, in items: [TodoItem]) -> TodoItem? {
        let q = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if let n = Int(q), n >= 1, n <= items.count { return items[n - 1] }
        let lq = q.lowercased()
        let pool = items.sorted { !$0.done && $1.done }   // open first
        if let exact = pool.first(where: { $0.title.lowercased() == lq }) { return exact }
        return pool.first { $0.title.lowercased().contains(lq) }
    }
}
