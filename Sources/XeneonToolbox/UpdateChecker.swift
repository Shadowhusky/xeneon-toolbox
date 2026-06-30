import Foundation
import AppKit

struct UpdateInfo: Equatable {
    let version: String        // normalized, e.g. "1.3.0"
    let name: String           // release title
    let notes: String          // markdown body (the changelog)
    let pageURL: URL           // release page
    let downloadURL: URL?      // best .zip asset, if present
}

/// Progress of an in-app self-update.
enum InstallPhase: Equatable { case idle, working(String), failed(String) }

struct UpdateError: Error { let message: String }

/// Checks GitHub Releases for a newer version on launch and at an interval, shows
/// a changelog, and — when running from an installed `.app` — downloads the
/// notarized zip, verifies it, and replaces itself in place before relaunching.
/// Falls back to opening the download page for non-bundle (dev) builds.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Set when a newer release is found that the user hasn't skipped or snoozed.
    @Published var available: UpdateInfo?
    @Published var checking = false
    @Published var statusLine = ""
    @Published var install: InstallPhase = .idle

    private let repo = "Shadowhusky/xeneon-toolbox"
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    private let interval: TimeInterval = 6 * 3600
    private var timer: Timer?

    /// "Ignore this time" — kept only in memory, so it clears on relaunch and the
    /// interval checks stay quiet for this session until the app is reopened.
    private var snoozedThisSession: Set<String> = []

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "update.skippedVersion") }
        set { UserDefaults.standard.setValue(newValue, forKey: "update.skippedVersion") }
    }

    /// Begin automatic checks. No-op when running as a bare executable (no bundle
    /// version), so dev builds don't nag.
    func start() {
        guard currentVersion != nil else { return }
        check()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// `manual` checks (from Settings) bypass skip/snooze and always show a found
    /// update; automatic checks respect the user's earlier choices.
    func check(manual: Bool = false) {
        guard !checking else { return }
        checking = true
        Task { await perform(manual: manual) }
    }

    private func perform(manual: Bool) async {
        defer { checking = false }
        guard let info = await fetchLatest() else {
            if manual { statusLine = "Couldn't reach the update server." }
            return
        }
        let current = currentVersion ?? "0"
        guard Self.compare(info.version, current) > 0 else {
            statusLine = "You're on the latest version (v\(current))."
            if manual { available = nil }
            return
        }
        statusLine = "Version \(info.version) is available."
        if !manual {
            if skippedVersion == info.version { return }
            if snoozedThisSession.contains(info.version) { return }
        }
        available = info
    }

    private func fetchLatest() async -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("XeneonToolbox", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if (json["draft"] as? Bool) == true || (json["prerelease"] as? Bool) == true { return nil }
        guard let tag = json["tag_name"] as? String else { return nil }
        let version = Self.normalize(tag)
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Version \(version)"
        let notes = (json["body"] as? String) ?? ""
        let pageURL = (json["html_url"] as? String).flatMap(URL.init)
            ?? URL(string: "https://github.com/\(repo)/releases/latest")!
        var download: URL?
        if let assets = json["assets"] as? [[String: Any]],
           let zip = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }),
           let s = zip["browser_download_url"] as? String {
            download = URL(string: s)
        }
        return UpdateInfo(version: version, name: name, notes: notes, pageURL: pageURL, downloadURL: download)
    }

    // MARK: - User actions

    /// Whether we can replace ourselves in place (running from an installed .app).
    var canSelfInstall: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    func update(_ info: UpdateInfo) {
        guard canSelfInstall, let zip = info.downloadURL else {
            NSWorkspace.shared.open(info.downloadURL ?? info.pageURL)
            available = nil
            return
        }
        Task { await selfInstall(from: zip) }
    }

    func openDownload(_ info: UpdateInfo) {
        NSWorkspace.shared.open(info.downloadURL ?? info.pageURL)
        available = nil
    }

    /// Download → unzip → verify signature/notarization/team → swap the bundle and
    /// relaunch via a small detached helper that waits for this process to exit.
    private func selfInstall(from url: URL) async {
        install = .working("Downloading update…")
        let oldApp = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            let (downloaded, resp) = try await URLSession.shared.download(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message: "Download failed.") }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("xeneon-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zipPath = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zipPath)

            install = .working("Verifying…")
            let newApp = try await Task.detached(priority: .userInitiated) {
                try UpdateChecker.unpackAndVerify(zip: zipPath, work: work, oldApp: oldApp)
            }.value

            install = .working("Installing…")
            try UpdateChecker.relaunchHelper(pid: pid, oldApp: oldApp, newApp: newApp.path, work: work)
            // The helper now waits for us to quit, swaps the bundle, and reopens it.
            NSApp.terminate(nil)
        } catch {
            install = .failed((error as? UpdateError)?.message ?? "Update failed. You can download it manually.")
        }
    }

    /// Unzips and confirms the update is intact, notarized, and from the same
    /// developer as the running app — never swap in something we can't trust.
    nonisolated private static func unpackAndVerify(zip: URL, work: URL, oldApp: String) throws -> URL {
        let unpack = work.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpack.path]).code == 0 else {
            throw UpdateError(message: "Couldn't unpack the update.")
        }
        guard let newApp = (try FileManager.default.contentsOfDirectory(at: unpack, includingPropertiesForKeys: nil))
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError(message: "Update didn't contain an app.") }

        guard run("/usr/bin/codesign", ["--verify", "--strict", newApp.path]).code == 0 else {
            throw UpdateError(message: "Update failed its signature check.")
        }
        guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path]).code == 0 else {
            throw UpdateError(message: "Update isn't notarized.")
        }
        let newTeam = teamID(newApp.path)
        if let oldTeam = teamID(oldApp), let newTeam, oldTeam != newTeam {
            throw UpdateError(message: "Update is signed by a different developer.")
        }
        return newApp
    }

    /// Writes and launches a detached shell helper. It outlives this process,
    /// waits for it to exit, replaces the bundle, and relaunches.
    nonisolated private static func relaunchHelper(pid: Int32, oldApp: String, newApp: String, work: URL) throws {
        let script = """
        #!/bin/sh
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "\(oldApp)"
        /usr/bin/ditto "\(newApp)" "\(oldApp)"
        /usr/bin/xattr -dr com.apple.quarantine "\(oldApp)" 2>/dev/null
        /usr/bin/open "\(oldApp)"
        /bin/rm -rf "\(work.path)"
        """
        let scriptURL = work.appendingPathComponent("apply.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [scriptURL.path]
        try p.run()   // detached: do not wait
    }

    nonisolated private static func teamID(_ appPath: String) -> String? {
        let out = run("/usr/bin/codesign", ["-dvvv", appPath]).output
        for line in out.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            return String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    nonisolated private static func run(_ launch: String, _ args: [String]) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func skip(_ info: UpdateInfo) { skippedVersion = info.version; available = nil }
    func ignoreThisTime(_ info: UpdateInfo) { snoozedThisSession.insert(info.version); available = nil }
    func dismiss() { available = nil }

    /// Inject a sample update for previewing the modal (XENEON_UPDATE_DEMO).
    func demo() {
        available = UpdateInfo(
            version: "9.9.9", name: "Preview",
            notes: """
            ## ✨ New
            - **Web tab** — open and save any site right on the Edge, with favicons.
            - **Fullscreen mode** — every page can fill the panel; games and the browser go fully immersive.

            ## 🛠 Improved
            - The phone remote can now push a URL straight to the Edge.

            ## 🐞 Fixed
            - The browser's Stop and Retry buttons now behave correctly.
            """,
            pageURL: URL(string: "https://github.com/\(repo)/releases/latest")!, downloadURL: nil)
    }

    // MARK: - Version helpers

    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    /// Numeric semver-ish compare: 1 if a>b, -1 if a<b, 0 if equal.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
