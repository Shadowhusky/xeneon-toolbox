import AppKit
import SwiftUI

enum DeckKind: String, Codable { case app, url, system, media, command, webhook, keystroke, multi
    var order: Int { switch self { case .multi: 0; case .app: 1; case .url: 2; case .keystroke: 3; case .command: 4; case .webhook: 5; case .system: 6; case .media: 7 } }
    var groupLabel: String { switch self { case .app: "App"; case .url: "Website"; case .command: "Command"; case .webhook: "Webhook"; case .system: "System"; case .media: "Media"; case .keystroke: "Hotkey"; case .multi: "Multi" } }
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
    case emptyTrash, screensaver, darkMode, keepAwake
    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .missionControl: return "Mission Control"
        case .launchpad: return "Launchpad"
        case .screenshot: return "Screenshot"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        case .emptyTrash: return "Empty Trash"
        case .screensaver: return "Screen Saver"
        case .darkMode: return "Toggle Dark Mode"
        case .keepAwake: return "Keep Awake"
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
        case .emptyTrash: return "trash.fill"
        case .screensaver: return "photo.on.rectangle.angled"
        case .darkMode: return "circle.lefthalf.filled"
        case .keepAwake: return "cup.and.saucer.fill"
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
    var keyCode: Int? = nil            // keystroke: virtual key code
    var modifiers: UInt? = nil         // keystroke: NSEvent.ModifierFlags raw value
    var steps: [DeckAction]? = nil     // multi: actions run in order (snapshots, never .multi)
    var preferredDisplay: String? = nil // app: display name to always open on (else the main display)

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
    static func keystroke(keyCode: Int, modifiers: UInt, display: String, label: String, symbol: String, iconPath: String?) -> DeckAction {
        DeckAction(kind: .keystroke, label: label, target: display, symbol: symbol, iconPath: iconPath,
                   keyCode: keyCode, modifiers: modifiers)
    }
    static func multi(_ steps: [DeckAction], label: String) -> DeckAction {
        DeckAction(kind: .multi, label: label, target: "\(steps.count) steps", symbol: "square.stack.3d.down.right.fill",
                   steps: steps.filter { $0.kind != .multi })   // no nesting — keeps runs finite
    }

    /// A stable key for lists (paths and raw values are unique per kind).
    var key: String { "\(kind.rawValue):\(target)" }

    static func appName(_ path: String) -> String {
        (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    /// An uploaded custom icon, if any — takes priority over the app icon / symbol.
    var customImage: NSImage? {
        guard let p = iconPath, FileManager.default.fileExists(atPath: p) else { return nil }
        if let cached = DeckIconCache.shared.object(forKey: p as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: p) else { return nil }
        DeckIconCache.shared.setObject(image, forKey: p as NSString)
        return image
    }

    /// Real app icon for `.app` tiles (nil for everything else).
    var appIcon: NSImage? {
        guard kind == .app, FileManager.default.fileExists(atPath: target) else { return nil }
        if let cached = DeckIconCache.shared.object(forKey: target as NSString) { return cached }
        let img = NSWorkspace.shared.icon(forFile: target)
        img.size = NSSize(width: 96, height: 96)
        DeckIconCache.shared.setObject(img, forKey: target as NSString)
        return img
    }
}

private enum DeckIconCache {
    static let shared = NSCache<NSString, NSImage>()
}

struct DeckPage: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var actions: [DeckAction]
    var manuallyOrdered = false

    private enum CodingKeys: String, CodingKey { case id, name, actions, manuallyOrdered }

    init(id: UUID = UUID(), name: String, actions: [DeckAction], manuallyOrdered: Bool = false) {
        self.id = id
        self.name = name
        self.actions = actions
        self.manuallyOrdered = manuallyOrdered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Deck"
        actions = try c.decodeIfPresent([DeckAction].self, forKey: .actions) ?? []
        manuallyOrdered = try c.decodeIfPresent(Bool.self, forKey: .manuallyOrdered) ?? false
    }
}

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var pages: [DeckPage]
    @Published private(set) var selectedPageID: DeckPage.ID

    private let pagesKey = "deck.pages.v2"
    private let selectedPageKey = "deck.selectedPage.v2"
    private let legacyActionsKey = "deck.actions.v1"
    private let legacyManualKey = "deck.manuallyOrdered"

    init() {
        let loadedPages: [DeckPage]
        if let data = AppDefaults.shared.data(forKey: pagesKey),
           let saved = try? JSONDecoder().decode([DeckPage].self, from: data),
           !saved.isEmpty {
            loadedPages = saved
        } else {
            let legacy: [DeckAction]
            if let data = AppDefaults.shared.data(forKey: legacyActionsKey),
               let saved = try? JSONDecoder().decode([DeckAction].self, from: data) {
                legacy = saved
            } else {
                legacy = Self.defaults()
            }
            loadedPages = [DeckPage(name: "Main", actions: legacy,
                                    manuallyOrdered: AppDefaults.shared.bool(forKey: legacyManualKey))]
        }
        pages = loadedPages
        let savedID = AppDefaults.shared.string(forKey: selectedPageKey).flatMap(UUID.init(uuidString:))
        selectedPageID = loadedPages.contains(where: { $0.id == savedID }) ? savedID! : loadedPages[0].id
        persist()
    }

    var selectedPage: DeckPage {
        pages.first(where: { $0.id == selectedPageID }) ?? pages[0]
    }
    var actions: [DeckAction] { selectedPage.actions }
    var manuallyOrdered: Bool { selectedPage.manuallyOrdered }
    var canRemovePage: Bool { pages.count > 1 }

    func selectPage(_ id: DeckPage.ID) {
        guard pages.contains(where: { $0.id == id }), selectedPageID != id else { return }
        selectedPageID = id
        AppDefaults.shared.set(id.uuidString, forKey: selectedPageKey)
    }

    @discardableResult
    func addPage(named rawName: String? = nil) -> DeckPage.ID {
        let fallback = "Page \(pages.count + 1)"
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let page = DeckPage(name: trimmed.isEmpty ? fallback : trimmed, actions: [])
        pages.append(page)
        selectedPageID = page.id
        persist()
        return page.id
    }

    func renamePage(_ id: DeckPage.ID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].name = name
        persist()
    }

    func removePage(_ id: DeckPage.ID) {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let removed = pages.remove(at: i)
        removed.actions.forEach { removeOwnedIconIfUnused($0.iconPath) }
        if selectedPageID == id { selectedPageID = pages[min(i, pages.count - 1)].id }
        persist()
    }

    func selectPreviousPage() {
        guard let i = pages.firstIndex(where: { $0.id == selectedPageID }), i > 0 else { return }
        selectPage(pages[i - 1].id)
    }

    func selectNextPage() {
        guard let i = pages.firstIndex(where: { $0.id == selectedPageID }), i + 1 < pages.count else { return }
        selectPage(pages[i + 1].id)
    }

    func add(_ a: DeckAction) {
        mutateSelected { $0.actions.append(a) }
    }

    func remove(_ id: DeckAction.ID) {
        guard let action = actions.first(where: { $0.id == id }) else { return }
        mutateSelected { $0.actions.removeAll { $0.id == id } }
        removeOwnedIconIfUnused(action.iconPath)
    }

    /// Edit an existing tile in place (rename, re-icon, or fix its target).
    func update(_ id: DeckAction.ID, label: String, symbol: String?, iconPath: String?, target: String?) {
        guard let old = actions.first(where: { $0.id == id }) else { return }
        var a = old
        a.label = label.isEmpty ? a.label : label
        if let symbol { a.symbol = symbol }
        a.iconPath = iconPath
        if let target, !target.isEmpty { a.target = target }
        mutateSelected { page in
            guard let i = page.actions.firstIndex(where: { $0.id == id }) else { return }
            page.actions[i] = a
        }
        if old.iconPath != iconPath { removeOwnedIconIfUnused(old.iconPath) }
    }

    /// Set (or clear, with nil) the display an app tile always opens on. Tapping
    /// the tile then opens it there directly instead of on the main display.
    func setPreferredDisplay(_ id: DeckAction.ID, _ name: String?) {
        mutateSelected { page in
            guard let i = page.actions.firstIndex(where: { $0.id == id }) else { return }
            page.actions[i].preferredDisplay = name
        }
    }

    /// Move `id` to sit before/after `target` — used by drag-to-reorder.
    func move(_ id: DeckAction.ID, target: DeckAction.ID, before: Bool) {
        guard id != target else { return }
        mutateSelected { page in
            guard let from = page.actions.firstIndex(where: { $0.id == id }) else { return }
            let item = page.actions.remove(at: from)
            guard var ti = page.actions.firstIndex(where: { $0.id == target }) else {
                page.actions.insert(item, at: min(from, page.actions.count))
                return
            }
            if !before { ti += 1 }
            page.actions.insert(item, at: min(max(0, ti), page.actions.count))
            page.manuallyOrdered = true
        }
    }

    func sort(_ mode: DeckSort) {
        mutateSelected { page in
            switch mode {
            case .name: page.actions.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            case .type: page.actions.sort {
                $0.kind.order != $1.kind.order ? $0.kind.order < $1.kind.order
                    : $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            }
            page.manuallyOrdered = false
        }
    }

    func reset() {
        let old = actions
        mutateSelected {
            $0.actions = Self.defaults()
            $0.manuallyOrdered = false
        }
        old.forEach { removeOwnedIconIfUnused($0.iconPath) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pages) { AppDefaults.shared.set(data, forKey: pagesKey) }
        AppDefaults.shared.set(selectedPageID.uuidString, forKey: selectedPageKey)
    }

    private func mutateSelected(_ change: (inout DeckPage) -> Void) {
        guard let i = pages.firstIndex(where: { $0.id == selectedPageID }) else { return }
        change(&pages[i])
        persist()
    }

    private func removeOwnedIconIfUnused(_ path: String?) {
        guard let path, path.contains("/XeneonToolbox/deck-icons/") else { return }
        let stillUsed = pages.flatMap(\.actions).contains { $0.iconPath == path }
        if !stillUsed {
            DeckIconCache.shared.removeObject(forKey: path as NSString)
            try? FileManager.default.removeItem(atPath: path)
        }
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
    nonisolated static func installedApps() -> [String] {
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        let fm = FileManager.default
        var paths: [String] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") && item != "XeneonToolbox.app" {
                paths.append("\(dir)/\(item)")
            }
        }
        return paths.sorted { DeckAction.appName($0).localizedCaseInsensitiveCompare(DeckAction.appName($1)) == .orderedAscending }
    }
}
