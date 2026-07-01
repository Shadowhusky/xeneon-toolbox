import AppKit
import SwiftUI

enum DeckKind: String, Codable { case app, url, system, media, command, webhook
    var order: Int { switch self { case .app: 0; case .url: 1; case .command: 2; case .webhook: 3; case .system: 4; case .media: 5 } }
    var groupLabel: String { switch self { case .app: "App"; case .url: "Website"; case .command: "Command"; case .webhook: "Webhook"; case .system: "System"; case .media: "Media" } }
}

enum DeckSort: String, CaseIterable, Identifiable {
    case name, type
    var id: String { rawValue }
    var label: String { self == .name ? "Alphabetical" : "By type" }
    var icon: String { self == .name ? "textformat" : "square.grid.2x2" }
}

/// In-app actions the deck can run without launching anything.
enum DeckSystemAction: String, Codable, CaseIterable {
    case minimal, missionControl, launchpad, screenshot, lockScreen, sleepDisplay
    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .missionControl: return "Mission Control"
        case .launchpad: return "Launchpad"
        case .screenshot: return "Screenshot"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        }
    }
    var symbol: String {
        switch self {
        case .minimal: return "rectangle.compress.vertical"
        case .missionControl: return "rectangle.3.group.fill"
        case .launchpad: return "square.grid.3x3.fill"
        case .screenshot: return "camera.viewfinder"
        case .lockScreen: return "lock.fill"
        case .sleepDisplay: return "moon.zzz.fill"
        }
    }
}

enum DeckMediaAction: String, Codable, CaseIterable {
    case playPause, next, previous
    var label: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous"
        }
    }
    var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        }
    }
}

/// One deck tile. `target` holds the app path, URL string, or the raw value of the
/// system/media action, depending on `kind`.
struct DeckAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: DeckKind
    var label: String
    var target: String                 // app path / URL / raw action / command / webhook URL
    var symbol: String? = nil          // SF Symbol used when there's no uploaded icon
    var iconPath: String? = nil        // an uploaded custom image, overrides everything
    var tint: String? = nil
    var httpMethod: String? = nil      // webhook: GET / POST
    var httpBody: String? = nil        // webhook: optional request body

    static func app(path: String) -> DeckAction {
        DeckAction(kind: .app, label: appName(path), target: path)
    }
    static func url(_ url: String, label: String) -> DeckAction {
        DeckAction(kind: .url, label: label, target: url, symbol: "globe")
    }
    static func system(_ a: DeckSystemAction) -> DeckAction {
        DeckAction(kind: .system, label: a.label, target: a.rawValue, symbol: a.symbol)
    }
    static func media(_ a: DeckMediaAction) -> DeckAction {
        DeckAction(kind: .media, label: a.label, target: a.rawValue, symbol: a.symbol)
    }
    static func command(_ cmd: String, label: String, symbol: String, iconPath: String?) -> DeckAction {
        DeckAction(kind: .command, label: label, target: cmd, symbol: symbol, iconPath: iconPath)
    }
    static func webhook(_ url: String, method: String, body: String?, label: String, symbol: String, iconPath: String?) -> DeckAction {
        DeckAction(kind: .webhook, label: label, target: url, symbol: symbol, iconPath: iconPath, httpMethod: method, httpBody: body)
    }

    /// A stable key for lists (paths and raw values are unique per kind).
    var key: String { "\(kind.rawValue):\(target)" }

    static func appName(_ path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    /// An uploaded custom icon, if any — takes priority over the app icon / symbol.
    var customImage: NSImage? {
        guard let p = iconPath, FileManager.default.fileExists(atPath: p) else { return nil }
        return NSImage(contentsOfFile: p)
    }

    /// Real app icon for `.app` tiles (nil for everything else).
    var appIcon: NSImage? {
        guard kind == .app, FileManager.default.fileExists(atPath: target) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: target)
        img.size = NSSize(width: 96, height: 96)
        return img
    }
}

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var actions: [DeckAction]
    @Published private(set) var manuallyOrdered: Bool
    private let key = "deck.actions.v1"
    private let manualKey = "deck.manuallyOrdered"

    init() {
        if let data = AppDefaults.shared.data(forKey: key),
           let saved = try? JSONDecoder().decode([DeckAction].self, from: data) {
            actions = saved
        } else {
            actions = Self.defaults()
        }
        manuallyOrdered = AppDefaults.shared.bool(forKey: manualKey)
    }

    func add(_ a: DeckAction) { actions.append(a); persist() }
    func remove(_ id: DeckAction.ID) { actions.removeAll { $0.id == id }; persist() }

    /// Move `id` to sit before/after `target` — used by drag-to-reorder.
    func move(_ id: DeckAction.ID, target: DeckAction.ID, before: Bool) {
        guard id != target, let from = actions.firstIndex(where: { $0.id == id }) else { return }
        let item = actions.remove(at: from)
        guard var ti = actions.firstIndex(where: { $0.id == target }) else {
            actions.insert(item, at: min(from, actions.count)); return
        }
        if !before { ti += 1 }
        actions.insert(item, at: min(max(0, ti), actions.count))
        setManual(true); persist()
    }

    func sort(_ mode: DeckSort) {
        switch mode {
        case .name: actions.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case .type: actions.sort {
            $0.kind.order != $1.kind.order ? $0.kind.order < $1.kind.order
                : $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        }
        setManual(false); persist()
    }

    func reset() { actions = Self.defaults(); setManual(false); persist() }

    private func setManual(_ v: Bool) {
        manuallyOrdered = v
        AppDefaults.shared.set(v, forKey: manualKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(actions) { AppDefaults.shared.set(data, forKey: key) }
    }

    /// A useful starter deck: whichever common apps are installed, plus a couple of
    /// in-app system and media actions.
    static func defaults() -> [DeckAction] {
        let candidates = [
            "/Applications/Safari.app", "/System/Applications/Safari.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Music.app",
            "/System/Applications/Messages.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/System Settings.app",
            "/System/Applications/Utilities/Terminal.app",
        ]
        var seen = Set<String>()
        var out: [DeckAction] = []
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let name = DeckAction.appName(path)
            if seen.insert(name).inserted { out.append(.app(path: path)) }
        }
        out.append(.system(.missionControl))
        out.append(.system(.screenshot))
        out.append(.media(.playPause))
        return out
    }

    /// Copy an uploaded image into an app-owned folder and return its path, so the
    /// icon survives even if the original file is moved or deleted.
    static func importIcon(from url: URL) -> String? {
        let fm = FileManager.default
        guard let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSup.appendingPathComponent("XeneonToolbox/deck-icons", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let dest = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        do { try fm.copyItem(at: url, to: dest); return dest.path } catch { return nil }
    }

    /// Installed apps for the picker, sorted by name.
    static func installedApps() -> [String] {
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        let fm = FileManager.default
        var paths: [String] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") { paths.append("\(dir)/\(item)") }
        }
        return paths.sorted { DeckAction.appName($0).localizedCaseInsensitiveCompare(DeckAction.appName($1)) == .orderedAscending }
    }
}
