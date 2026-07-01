import Foundation

/// A stable, bundle-independent defaults store so configuration persists the same
/// whether the app runs from the notarized bundle or a dev build — both share the
/// suite named after the release bundle id. Migrates any pre-existing standard
/// values across on first use.
enum AppDefaults {
    static let suiteName = "com.shadowhusky.xeneon-toolbox"

    static let shared: UserDefaults = {
        guard let suite = UserDefaults(suiteName: suiteName) else { return .standard }
        if !suite.bool(forKey: "migrated.suite.v1") {
            let std = UserDefaults.standard
            for (k, v) in std.dictionaryRepresentation() where isConfigKey(k) {
                if suite.object(forKey: k) == nil { suite.set(v, forKey: k) }
            }
            suite.set(true, forKey: "migrated.suite.v1")
        }
        return suite
    }()

    /// The keys that make up the user's configuration (for iCloud backup/restore).
    static let configPrefixes = ["deck.", "dashboard.", "ui.", "touch.", "remote.", "tutorial.", "update.", "chat", "weather", "worldclocks", "webapps"]

    static func isConfigKey(_ k: String) -> Bool { configPrefixes.contains { k.hasPrefix($0) } }
}
