import Foundation

/// A saved web page shown on the Web tab's launchpad.
struct WebApp: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var urlString: String
}

/// Owns the user's saved web pages: persists to disk and seeds a small default
/// set on first run. Mirrors WorldClockStore.
@MainActor
final class WebAppStore: ObservableObject {
    @Published private(set) var apps: [WebApp] = []

    private static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox/webapps.json")
    }

    private static let defaults: [WebApp] = [
        WebApp(title: "YouTube", urlString: "https://www.youtube.com"),
        WebApp(title: "YouTube Music", urlString: "https://music.youtube.com"),
        WebApp(title: "Wikipedia", urlString: "https://www.wikipedia.org"),
        WebApp(title: "Hacker News", urlString: "https://news.ycombinator.com"),
    ]

    init() { load() }

    @discardableResult
    func add(title: String, urlString: String) -> WebApp? {
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        let name = title.trimmingCharacters(in: .whitespaces)
        // Avoid duplicates of the same site, even when one path saved it with a
        // trailing slash / www and another without (e.g. address-bar vs Add dialog).
        let key = Self.canonicalKey(url)
        if apps.contains(where: { Self.canonicalKey($0.urlString) == key }) { return nil }
        let app = WebApp(title: name.isEmpty ? Self.displayName(url) : name, urlString: url)
        apps.append(app)
        save()
        return app
    }

    func remove(_ id: UUID) {
        apps.removeAll { $0.id == id }
        save()
    }

    func resetToDefaults() {
        apps = Self.defaults
        save()
    }

    /// Canonical identity for dedupe: host (without "www.") + path (no trailing
    /// slash) + query, scheme/fragment ignored.
    static func canonicalKey(_ s: String) -> String {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: raw) ?? URLComponents(string: "https://\(raw)") else { return raw.lowercased() }
        var host = (c.host ?? "").lowercased()
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        var path = c.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return host + path + (c.query.map { "?\($0)" } ?? "")
    }

    /// A readable label from a URL (host without "www."), for unnamed bookmarks.
    static func displayName(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host ?? URL(string: "https://\(urlString)")?.host else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode([WebApp].self, from: data) else {
            apps = Self.defaults
            return
        }
        apps = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(apps) { try? data.write(to: Self.storeURL) }
    }
}
