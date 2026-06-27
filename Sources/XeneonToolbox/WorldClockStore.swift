import Foundation
import ToolboxKit

/// Owns the user's world-clock cities: persists to disk, seeds a sensible
/// default set on first run. Shared by the Clock UI and the assistant.
@MainActor
final class WorldClockStore: ObservableObject {
    @Published private(set) var clocks: [WorldClock] = []

    private static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox/worldclocks.json")
    }

    private static let defaults: [WorldClock] = [
        WorldClock(name: "San Francisco", timeZoneID: "America/Los_Angeles"),
        WorldClock(name: "New York", timeZoneID: "America/New_York"),
        WorldClock(name: "London", timeZoneID: "Europe/London"),
        WorldClock(name: "Tokyo", timeZoneID: "Asia/Tokyo"),
    ]

    init() { load() }

    @discardableResult
    func add(name: String, timeZoneID: String) -> WorldClock? {
        guard TimeZone(identifier: timeZoneID) != nil else { return nil }
        // Avoid exact duplicates (same name + zone).
        if clocks.contains(where: { $0.name == name && $0.timeZoneID == timeZoneID }) { return nil }
        let clock = WorldClock(name: name, timeZoneID: timeZoneID)
        clocks.append(clock)
        save()
        return clock
    }

    @discardableResult
    func add(_ clock: WorldClock) -> WorldClock? { add(name: clock.name, timeZoneID: clock.timeZoneID) }

    func remove(_ id: UUID) {
        clocks.removeAll { $0.id == id }
        save()
    }

    /// Remove by free-text city name (for the assistant). Returns whether it matched.
    @discardableResult
    func remove(name: String) -> Bool {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        let before = clocks.count
        clocks.removeAll { $0.name.lowercased() == q }
        if clocks.count == before { clocks.removeAll { $0.name.lowercased().contains(q) } }
        if clocks.count != before { save(); return true }
        return false
    }

    func move(from offsets: IndexSet, to destination: Int) {
        clocks.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func resetToDefaults() {
        clocks = Self.defaults
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode([WorldClock].self, from: data) else {
            clocks = Self.defaults
            return
        }
        clocks = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(clocks) { try? data.write(to: Self.storeURL) }
    }
}
