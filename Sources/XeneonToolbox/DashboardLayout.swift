import Foundation

/// The dashboard's gadgets, identified so their order and visibility can be saved.
enum DashTile: String, CaseIterable, Codable, Identifiable {
    case clock, cpu, gpu, memory, network, storage, power, controls
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
        case .controls: return "Configs"
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
        case .controls: return "slider.horizontal.3"
        }
    }
}

/// Persisted dashboard arrangement: the tile order and which tiles are hidden.
/// Reordering and hiding happen in the dashboard's edit mode; both survive
/// relaunch. New tiles added in future versions are appended automatically so an
/// old saved layout never loses them.
@MainActor
final class DashboardLayout: ObservableObject {
    @Published private(set) var order: [DashTile]
    @Published private(set) var hidden: Set<DashTile>

    private let key = "dashboard.layout.v1"

    private struct Saved: Codable { var order: [DashTile]; var hidden: [DashTile] }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            let known = saved.order.filter { DashTile.allCases.contains($0) }
            let missing = DashTile.allCases.filter { !known.contains($0) }
            order = known + missing
            hidden = Set(saved.hidden).intersection(DashTile.allCases)
        } else {
            order = DashTile.allCases
            hidden = []
        }
    }

    var visible: [DashTile] { order.filter { !hidden.contains($0) } }

    func isHidden(_ tile: DashTile) -> Bool { hidden.contains(tile) }

    /// Move `tile` to occupy `target`'s slot, choosing the side from `before`.
    func move(_ tile: DashTile, toward target: DashTile, before: Bool) {
        guard tile != target, let from = order.firstIndex(of: tile) else { return }
        order.remove(at: from)
        guard let t = order.firstIndex(of: target) else { order.insert(tile, at: min(from, order.count)); return }
        order.insert(tile, at: before ? t : t + 1)
    }

    func hide(_ tile: DashTile) {
        guard visible.count > 1 else { return }   // never hide the last visible tile
        hidden.insert(tile)
        save()
    }

    func show(_ tile: DashTile) {
        hidden.remove(tile)
        // Bring a re-shown tile to the end of the visible run so it's easy to find.
        if let i = order.firstIndex(of: tile) { order.remove(at: i); order.append(tile) }
        save()
    }

    func save() {
        let s = Saved(order: order, hidden: Array(hidden))
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: key) }
    }

    func reset() {
        order = DashTile.allCases
        hidden = []
        save()
    }
}
