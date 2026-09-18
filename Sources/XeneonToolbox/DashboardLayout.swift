import Foundation
import ToolboxKit

/// The dashboard's gadgets, identified so a board can be saved.
enum DashTile: String, CaseIterable, Codable, Identifiable {
    case clock, cpu, gpu, memory, network, storage, power, upNext, tasks, thermals, dock, clipboard, nowPlaying
    case focus, worldClocks, weather, devices, quickActions
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .cpu: return "Processor"
        case .gpu: return "Graphics"
        case .memory: return "Memory"
        case .network: return "Network"
        case .storage: return "Storage"
        case .power: return "Power"
        case .upNext: return "Up Next"
        case .tasks: return "Tasks"
        case .thermals: return "Thermals"
        case .dock: return "Running apps"
        case .clipboard: return "Clipboard"
        case .nowPlaying: return "Now Playing"
        case .focus: return "Focus"
        case .worldClocks: return "World clocks"
        case .weather: return "Weather"
        case .devices: return "Devices"
        case .quickActions: return "Quick actions"
        }
    }

    var icon: String {
        switch self {
        case .clock: return "clock.fill"
        case .cpu: return "cpu.fill"
        case .gpu: return "cube.transparent.fill"
        case .memory: return "memorychip.fill"
        case .network: return "dot.radiowaves.up.forward"
        case .storage: return "internaldrive.fill"
        case .power: return "powerplug.fill"
        case .upNext: return "calendar"
        case .tasks: return "checklist"
        case .thermals: return "thermometer.medium"
        case .dock: return "macwindow.on.rectangle"
        case .clipboard: return "doc.on.clipboard"
        case .nowPlaying: return "music.note"
        case .focus: return "timer"
        case .worldClocks: return "globe"
        case .weather: return "cloud.sun.fill"
        case .devices: return "wave.3.right"
        case .quickActions: return "bolt.fill"
        }
    }

    /// One line for the tile gallery.
    var blurb: String {
        switch self {
        case .clock: return "Time, date and the local weather. Tap for the forecast."
        case .cpu: return "Processor load with a live history. Tap for the top processes."
        case .gpu: return "Graphics load with a live history."
        case .memory: return "Memory in use and pressure. Tap for the biggest apps."
        case .network: return "Download and upload rates. Tap for details."
        case .storage: return "Free space on the startup disk."
        case .power: return "Battery or live system draw. Tap for the energy flow."
        case .upNext: return "Your next calendar events today. Tap for the agenda."
        case .tasks: return "Open tasks and reminders you can tick off in place."
        case .thermals: return "Chip temperature and fan speed."
        case .dock: return "Every running app — tap one to bring it forward."
        case .clipboard: return "The last few things you copied. Tap to copy again."
        case .nowPlaying: return "Spotify or Music, with playback controls."
        case .focus: return "A focus timer you can start and pause from the board."
        case .worldClocks: return "The cities from your Clock page, at a glance."
        case .weather: return "Current conditions with the next hours. Tap for the forecast."
        case .devices: return "Connected Bluetooth devices and their charge."
        case .quickActions: return "Keep awake, dark mode, screenshot, lock and more."
        }
    }

    var sizes: [TileSize] {
        switch self {
        case .clock: return [.t, .s, .w]
        case .cpu, .gpu, .memory, .network: return [.s, .w]
        case .storage, .power, .thermals: return [.s]
        case .upNext, .dock: return [.w, .s]
        case .tasks, .clipboard, .nowPlaying: return [.s, .w]
        case .focus: return [.s]
        case .worldClocks, .weather, .quickActions: return [.w, .s]
        case .devices: return [.s, .w]
        }
    }

    var defaultSize: TileSize { sizes[0] }
}

enum TileSize: String, Codable, CaseIterable {
    case s, w, t, l
    var columns: Int { self == .w || self == .l ? 2 : 1 }
    var rows: Int { self == .t || self == .l ? 2 : 1 }
    var cells: Int { columns * rows }
    var label: String { rawValue.uppercased() }
    var name: String {
        switch self { case .s: return "Small"; case .w: return "Wide"; case .t: return "Tall"; case .l: return "Large" }
    }
}

struct PlacedTile: Codable, Equatable, Identifiable {
    let tile: DashTile
    var size: TileSize
    var id: DashTile { tile }
}

/// The dashboard board: which tiles, at what size, in what order. Placement on
/// the 2×8 grid is derived by first-fit packing, so the user only ever reorders
/// a list. Persists as `dashboard.layout.v2`; a v1 order migrates once.
@MainActor
final class DashboardLayout: ObservableObject {
    static let columns = 8
    static let rows = 2
    static let capacity = columns * rows

    @Published private(set) var board: [PlacedTile] { didSet { repack() } }
    private(set) var slots: [DashTile: GridSlot] = [:]
    private(set) var overflow: [DashTile] = []

    private let key = "dashboard.layout.v2"
    private let legacyKey = "dashboard.layout.v1"

    static let defaultBoard: [PlacedTile] = [
        .init(tile: .clock, size: .t), .init(tile: .cpu, size: .s), .init(tile: .gpu, size: .s),
        .init(tile: .memory, size: .s), .init(tile: .network, size: .w), .init(tile: .storage, size: .s),
        .init(tile: .power, size: .s), .init(tile: .upNext, size: .w), .init(tile: .tasks, size: .s),
        .init(tile: .thermals, size: .s), .init(tile: .dock, size: .w), .init(tile: .nowPlaying, size: .s),
    ]

    private struct SavedTile: Codable { let tile: String; let size: String }
    private struct SavedV1: Codable { var order: [String]; var hidden: [String] }

    init() {
        // XENEON_BOARD="clock:t,cpu:s,…" renders a given board without touching the saved one.
        if let spec = ProcessInfo.processInfo.environment["XENEON_BOARD"] {
            board = Self.sanitized(spec.split(separator: ",").compactMap { item in
                let parts = item.split(separator: ":").map(String.init)
                guard let t = DashTile(rawValue: parts[0]) else { return nil }
                return PlacedTile(tile: t, size: parts.count > 1 ? (TileSize(rawValue: parts[1]) ?? t.defaultSize) : t.defaultSize)
            })
            repack()
            return
        }
        if let data = AppDefaults.shared.data(forKey: key),
           let saved = try? JSONDecoder().decode([SavedTile].self, from: data), !saved.isEmpty {
            board = Self.sanitized(saved.compactMap { s in
                guard let t = DashTile(rawValue: s.tile) else { return nil }
                return PlacedTile(tile: t, size: TileSize(rawValue: s.size) ?? t.defaultSize)
            })
        } else if let data = AppDefaults.shared.data(forKey: legacyKey),
                  let v1 = try? JSONDecoder().decode(SavedV1.self, from: data) {
            // Keep the v1 order for the tiles that still exist (the old Configs
            // tile is gone), then append the new gadgets at their default sizes.
            let kept = v1.order.compactMap(DashTile.init(rawValue:)).filter { !v1.hidden.contains($0.rawValue) }
                .map { tile in PlacedTile(tile: tile, size: Self.defaultBoard.first { $0.tile == tile }?.size ?? tile.defaultSize) }
            let missing = Self.defaultBoard.filter { d in !kept.contains { $0.tile == d.tile } }
            board = Self.sanitized(kept + missing)
        } else {
            board = Self.defaultBoard
        }
        repack()
        save()
    }

    private static func sanitized(_ tiles: [PlacedTile]) -> [PlacedTile] {
        var seen = Set<DashTile>()
        var out: [PlacedTile] = []
        for var t in tiles where !seen.contains(t.tile) {
            seen.insert(t.tile)
            if !t.tile.sizes.contains(t.size) { t.size = t.tile.defaultSize }
            out.append(t)
        }
        return out.isEmpty ? defaultBoard : out
    }

    var available: [DashTile] { DashTile.allCases.filter { t in !board.contains { $0.tile == t } } }
    var cellsUsed: Int { board.reduce(0) { $0 + $1.size.cells } }
    func contains(_ tile: DashTile) -> Bool { board.contains { $0.tile == tile } }
    func size(of tile: DashTile) -> TileSize? { board.first { $0.tile == tile }?.size }

    /// Move `tile` to sit before/after `target` — drag-to-reorder.
    func move(_ tile: DashTile, toward target: DashTile, before: Bool) {
        guard tile != target, let from = board.firstIndex(where: { $0.tile == tile }) else { return }
        let item = board.remove(at: from)
        guard let t = board.firstIndex(where: { $0.tile == target }) else { board.insert(item, at: min(from, board.count)); return }
        board.insert(item, at: before ? t : t + 1)
    }

    func remove(_ tile: DashTile) {
        guard board.count > 1 else { return }   // never empty the board
        board.removeAll { $0.tile == tile }
        save()
    }

    /// Adds at `size`; false when it wouldn't fit (cells or packing geometry).
    @discardableResult
    func add(_ tile: DashTile, size: TileSize) -> Bool {
        guard !contains(tile), tile.sizes.contains(size), cellsUsed + size.cells <= Self.capacity else { return false }
        let old = board
        board.append(PlacedTile(tile: tile, size: size))
        guard overflow.isEmpty else { board = old; return false }
        save()
        return true
    }

    /// Resizes in place; false when the new size wouldn't fit.
    @discardableResult
    func setSize(_ tile: DashTile, _ size: TileSize) -> Bool {
        guard tile.sizes.contains(size), let i = board.firstIndex(where: { $0.tile == tile }) else { return false }
        let old = board
        board[i].size = size
        guard overflow.isEmpty else { board = old; return false }
        save()
        return true
    }

    /// The next supported size for a tile (cycles).
    func nextSize(for tile: DashTile) -> TileSize? {
        guard let cur = size(of: tile), let i = tile.sizes.firstIndex(of: cur), tile.sizes.count > 1 else { return nil }
        return tile.sizes[(i + 1) % tile.sizes.count]
    }

    func reset() {
        board = Self.defaultBoard
        save()
    }

    func save() {
        let saved = board.map { SavedTile(tile: $0.tile.rawValue, size: $0.size.rawValue) }
        if let data = try? JSONEncoder().encode(saved) { AppDefaults.shared.set(data, forKey: key) }
    }

    private func repack() {
        let r = GridPacker.pack(board.map { PackedItem(id: $0.tile, columns: $0.size.columns, rows: $0.size.rows) },
                                columns: Self.columns, rows: Self.rows)
        slots = r.placed
        overflow = r.overflow
    }
}
