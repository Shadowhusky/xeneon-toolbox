import Foundation

/// The last few things copied, newest first. Pure so the ordering rules are
/// testable; the app feeds it pasteboard changes.
public struct ClipboardHistory: Equatable, Sendable {
    public private(set) var items: [String] = []
    public let capacity: Int

    public init(capacity: Int = 6) {
        self.capacity = max(1, capacity)
    }

    /// Newest first; copying something already in the list moves it to the
    /// front; whitespace-only text is ignored.
    public mutating func push(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > capacity { items.removeLast(items.count - capacity) }
    }

    public mutating func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    public mutating func removeAll() { items.removeAll() }
}
