import AppKit

/// Profiles for Chromium-family browsers (Chrome's "multiple users"), read from
/// the browser's `Local State` JSON. Opening one launches the app binary with
/// `--profile-directory=` — the running instance's process singleton picks it up
/// and focuses-or-creates that profile's window (no Apple-Events consent, works
/// whether or not the browser is already running). This is what makes the deck a
/// quick profile switcher.
enum ChromeProfiles {
    struct Profile: Identifiable, Equatable {
        let dir: String      // e.g. "Default", "Profile 3"
        let name: String     // display name, disambiguated when duplicated
        var id: String { dir }
    }

    /// Bundle id → user-data dir under ~/Library/Application Support.
    private static let dataDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "org.chromium.Chromium": "Chromium",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    static func isChromium(appPath: String) -> Bool {
        guard let id = Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier else { return false }
        return dataDirs[id] != nil
    }

    /// The browser's profiles, most-recently-used first. Empty when the app isn't
    /// a known Chromium browser or has a single default profile only.
    static func profiles(appPath: String) -> [Profile] {
        guard let bundleID = Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier,
              let sub = dataDirs[bundleID] else { return [] }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(sub)/Local State")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        let lastUsed = profile["last_used"] as? String

        var raw: [(dir: String, name: String, gaia: String)] = cache.map { dir, info in
            (dir, (info["name"] as? String) ?? dir, (info["gaia_name"] as? String) ?? "")
        }
        raw.sort { a, b in
            if (a.dir == lastUsed) != (b.dir == lastUsed) { return a.dir == lastUsed }
            return a.dir < b.dir
        }
        // Chrome lets several profiles share a display name — append the Google
        // account if that distinguishes them, else the profile folder (several
        // profiles can even share BOTH name and account).
        let nameCounts = Dictionary(grouping: raw, by: \.name).mapValues(\.count)
        let nameGaiaCounts = Dictionary(grouping: raw, by: { "\($0.name)|\($0.gaia)" }).mapValues(\.count)
        return raw.map { p in
            var name = p.name
            if nameCounts[p.name, default: 0] > 1 {
                if !p.gaia.isEmpty, p.gaia != p.name, nameGaiaCounts["\(p.name)|\(p.gaia)", default: 0] == 1 {
                    name += " · \(p.gaia)"
                } else {
                    name += " · \(p.dir)"
                }
            }
            return Profile(dir: p.dir, name: name)
        }
    }

    /// Focus-or-create a window for the profile via the process singleton.
    static func open(appPath: String, profileDir: String) {
        guard let exec = Bundle(url: URL(fileURLWithPath: appPath))?.executableURL else { return }
        AppLog.info("deck", "chrome profile '\(profileDir)' via \(exec.lastPathComponent)")
        let p = Process()
        p.executableURL = exec
        p.arguments = ["--profile-directory=\(profileDir)"]
        try? p.run()   // hands off to the running instance and exits on its own
    }
}
