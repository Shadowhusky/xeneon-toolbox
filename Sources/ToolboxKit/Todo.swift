import Foundation

/// A to-do / reminder item. `dueAt` set ⇒ it's a reminder (fires a notification).
public struct TodoItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var createdAt: Date
    public var dueAt: Date?

    public init(id: UUID = UUID(), title: String, done: Bool = false,
                createdAt: Date = Date(), dueAt: Date? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.dueAt = dueAt
    }

    public var isOverdue: Bool {
        guard !done, let d = dueAt else { return false }
        return d < Date()
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
