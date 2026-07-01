import Foundation
import AppKit

/// Back up / restore the app configuration to a JSON file in iCloud Drive (falls
/// back to ~/Documents when iCloud Drive is off), so config follows the user
/// across machines and reinstalls.
enum ConfigBackup {
    enum Outcome { case ok(String), fail(String) }

    static var iCloudDir: URL? {
        let icloud = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: icloud.path) ? icloud : nil
    }
    static var usingICloud: Bool { iCloudDir != nil }

    static var backupURL: URL {
        let base = iCloudDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let dir = base.appendingPathComponent("XeneonToolbox")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func export() -> Data? {
        var dict: [String: Any] = [:]
        for (k, v) in AppDefaults.shared.dictionaryRepresentation() where AppDefaults.isConfigKey(k) {
            if let data = v as? Data { dict[k] = ["__data__": data.base64EncodedString()] }
            else { dict[k] = v }
        }
        return try? JSONSerialization.data(withJSONObject: ["version": 1, "values": dict], options: [.prettyPrinted])
    }

    static func backup() -> Outcome {
        guard let data = export() else { return .fail("Nothing to back up") }
        do {
            try data.write(to: backupURL, options: .atomic)
            return .ok(usingICloud ? "Backed up to iCloud Drive" : "Saved to Documents (iCloud Drive is off)")
        } catch { return .fail("Couldn't write the backup") }
    }

    static func restore() -> Outcome {
        guard let data = try? Data(contentsOf: backupURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["values"] as? [String: Any] else {
            return .fail("No backup found")
        }
        for (k, v) in values {
            if let wrap = v as? [String: Any], let b64 = wrap["__data__"] as? String, let d = Data(base64Encoded: b64) {
                AppDefaults.shared.set(d, forKey: k)
            } else {
                AppDefaults.shared.set(v, forKey: k)
            }
        }
        return .ok("Restored — relaunching…")
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        if path.hasSuffix(".app") {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = [path]; try? p.run()
        }
        NSApp.terminate(nil)
    }
}
