import Foundation
import AppKit
import CryptoKit
import ToolboxKit

struct UpdateInfo: Equatable {
    let version: String        // normalized, e.g. "1.3.0"
    let name: String           // release title
    let notes: String          // markdown body (the changelog)
    let pageURL: URL           // release page
    let downloadURL: URL?      // best .zip asset, if present
    var sha256: String? = nil  // GitHub's asset digest, when it publishes one
}

/// Progress of an in-app self-update.
enum InstallPhase: Equatable { case idle, working(String), failed(String) }

struct UpdateError: Error { let message: String }

/// Keeps the app current without getting in the way. A newer GitHub release is
/// downloaded and verified in the background (signature, notarization, same
/// developer, matching version, optional digest), then installed at a quiet
/// moment: when nobody has touched the panel for a while, or on the next quit.
/// The user sees one small notice, and a "what's new" toast after the relaunch.
/// The swap keeps the previous bundle and rolls back if the new one doesn't
/// come up. "Ask first" shows the release instead; "Off" only checks on request.
@MainActor
final class UpdateChecker: ObservableObject {
    /// A release to show the user (Ask-first policy, or a manual check).
    @Published var available: UpdateInfo?
    /// Downloaded and verified on disk, waiting for a quiet moment.
    @Published private(set) var staged: UpdateInfo?
    /// The one quiet notice per staged version.
    @Published var showReadyNotice = false
    /// Set on the first launch of a version the updater installed.
    @Published private(set) var justUpdated: UpdateInfo?
    @Published var showWhatsNew = false
    @Published var checking = false
    @Published var statusLine = ""
    @Published var install: InstallPhase = .idle
    @Published var policy: UpdatePolicy {
        didSet {
            AppDefaults.shared.set(policy.rawValue, forKey: Self.policyKey)
            if policy == .automatic, let info = available, staged?.version != info.version { available = nil; stage(info) }
        }
    }

    /// Whether the panel is idle enough to relaunch unnoticed. Set by the model.
    var isQuiet: () -> Bool = { false }

    private let repo = "Shadowhusky/xeneon-toolbox"
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    private let interval: TimeInterval = 6 * 3600
    private var checkTimer: Timer?
    private var idleTimer: Timer?
    private var stagedApp: URL?
    private var noticedVersions: Set<String> = []
    private var snoozedThisSession: Set<String> = []
    private var etag: String?

    private static let policyKey = "update.policy"
    private static let installedVersionKey = "update.installedVersion"
    private static let installedNotesKey = "update.installedNotes"
    private static let installedNameKey = "update.installedName"

    private var skippedVersion: String? {
        get { AppDefaults.shared.string(forKey: "update.skippedVersion") }
        set { AppDefaults.shared.setValue(newValue, forKey: "update.skippedVersion") }
    }

    init() {
        policy = AppDefaults.shared.string(forKey: Self.policyKey).flatMap(UpdatePolicy.init(rawValue:)) ?? .automatic
    }

    /// Begin automatic checks. No-op when running as a bare executable (no bundle
    /// version), so dev builds don't nag.
    func start() {
        guard let current = currentVersion else { return }
        noteFreshInstall(current)
        restoreStagedFromDisk(current)
        // Don't compete with launch; then every ~6 h with jitter.
        scheduleCheck(after: 45)
    }

    private func scheduleCheck(after delay: TimeInterval) {
        checkTimer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.policy != .off { self.check() }
                self.scheduleCheck(after: UpdateStrategy.nextCheckDelay(base: self.interval, random: .random(in: 0..<1)))
            }
        }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        checkTimer = t
    }

    /// `manual` checks (from Settings) bypass skip/snooze and always show a found
    /// update; automatic checks follow the policy and the user's earlier choices.
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
        guard UpdateStrategy.compare(info.version, current) > 0 else {
            statusLine = "You're on the latest version (v\(current))."
            if manual { available = nil }
            return
        }
        if staged?.version == info.version {
            statusLine = "Version \(info.version) is ready to install."
            if manual { available = info }
            return
        }
        statusLine = "Version \(info.version) is available."
        if manual { available = info; return }
        guard skippedVersion != info.version, !snoozedThisSession.contains(info.version) else { return }
        switch policy {
        case .automatic: stage(info)
        case .notify: available = info
        case .off: break
        }
    }

    private func fetchLatest() async -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("XeneonToolbox/\(currentVersion ?? "dev")", forHTTPHeaderField: "User-Agent")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 304 { return lastFetched }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if (json["draft"] as? Bool) == true || (json["prerelease"] as? Bool) == true { return nil }
        guard let tag = json["tag_name"] as? String else { return nil }
        let version = UpdateStrategy.normalize(tag)
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Version \(version)"
        let notes = (json["body"] as? String) ?? ""
        let pageURL = (json["html_url"] as? String).flatMap(URL.init)
            ?? URL(string: "https://github.com/\(repo)/releases/latest")!
        var download: URL?
        var digest: String?
        if let assets = json["assets"] as? [[String: Any]],
           let zip = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }) {
            download = (zip["browser_download_url"] as? String).flatMap(URL.init)
            if let d = zip["digest"] as? String, d.hasPrefix("sha256:") { digest = String(d.dropFirst(7)).lowercased() }
        }
        etag = http.value(forHTTPHeaderField: "ETag")
        let info = UpdateInfo(version: version, name: name, notes: notes, pageURL: pageURL, downloadURL: download, sha256: digest)
        lastFetched = info
        return info
    }
    private var lastFetched: UpdateInfo?

    // MARK: - Staging (download + verify in the background)

    /// Whether we can replace ourselves in place (running from an installed .app).
    var canSelfInstall: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    private var stagingDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("XeneonToolbox/updates", isDirectory: true)
    }

    private func stage(_ info: UpdateInfo) {
        guard canSelfInstall, let zip = info.downloadURL, staged?.version != info.version, staging == nil else { return }
        staging = Task { await download(info, from: zip) }
    }
    private var staging: Task<Void, Never>?

    private func download(_ info: UpdateInfo, from url: URL) async {
        defer { staging = nil }
        let oldApp = Bundle.main.bundlePath
        let work = stagingDir.appendingPathComponent(info.version, isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: work)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // Not over hotspots or Low Data Mode; a missed check just tries again later.
            let config = URLSessionConfiguration.ephemeral
            config.allowsExpensiveNetworkAccess = false
            config.allowsConstrainedNetworkAccess = false
            config.timeoutIntervalForResource = 600
            let (downloaded, resp) = try await URLSession(configuration: config).download(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message: "Download failed.") }
            let zipPath = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zipPath)
            let expected = info.sha256, version = info.version
            let newApp = try await Task.detached(priority: .utility) {
                try UpdateChecker.unpackAndVerify(zip: zipPath, work: work, oldApp: oldApp, version: version, sha256: expected)
            }.value
            stagedApp = newApp
            staged = info
            statusLine = "Version \(info.version) is ready. It installs when you're away."
            AppLog.info("update", "v\(info.version) staged at \(newApp.path)")
            if !noticedVersions.contains(info.version) { noticedVersions.insert(info.version); showReadyNotice = true }
            startIdleWatch()
        } catch {
            let message = (error as? UpdateError)?.message ?? error.localizedDescription
            AppLog.error("update", "staging v\(info.version) failed: \(message)")
            statusLine = "Couldn't prepare v\(info.version): \(message)"
            try? FileManager.default.removeItem(at: work)
        }
    }

    /// A previous run may have staged an update it never got a quiet moment for.
    private func restoreStagedFromDisk(_ current: String) {
        guard canSelfInstall,
              let dirs = try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            let version = dir.lastPathComponent
            guard UpdateStrategy.compare(version, current) > 0,
                  let app = (try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("unpacked"), includingPropertiesForKeys: nil))?
                    .first(where: { $0.pathExtension == "app" }),
                  Self.run("/usr/bin/codesign", ["--verify", "--strict", app.path]).code == 0 else {
                try? FileManager.default.removeItem(at: dir)
                continue
            }
            stagedApp = app
            staged = UpdateInfo(version: version, name: "Version \(version)", notes: "", pageURL: URL(string: "https://github.com/\(repo)/releases/latest")!, downloadURL: nil)
            startIdleWatch()
            AppLog.info("update", "v\(version) still staged from an earlier run")
        }
    }

    private func startIdleWatch() {
        guard idleTimer == nil else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.staged != nil else { return }
                if self.policy == .automatic && self.isQuiet() { self.installNow() }
            }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    // MARK: - Installing

    /// Swap in the staged bundle and relaunch. Quiet by design: nothing to confirm.
    func installNow() {
        guard let info = staged, let newApp = stagedApp else { return }
        do {
            rememberInstall(info)
            try Self.relaunchHelper(pid: ProcessInfo.processInfo.processIdentifier, oldApp: Bundle.main.bundlePath,
                                    newApp: newApp.path, work: newApp.deletingLastPathComponent().deletingLastPathComponent(),
                                    relaunch: true)
            AppLog.info("update", "installing v\(info.version) now")
            NSApp.terminate(nil)
        } catch {
            install = .failed("Couldn't start the installer.")
        }
    }

    /// The app is quitting anyway: the cheapest possible moment to swap, no relaunch.
    func installAtQuit() {
        guard let info = staged, let newApp = stagedApp else { return }
        rememberInstall(info)
        try? Self.relaunchHelper(pid: ProcessInfo.processInfo.processIdentifier, oldApp: Bundle.main.bundlePath,
                                 newApp: newApp.path, work: newApp.deletingLastPathComponent().deletingLastPathComponent(),
                                 relaunch: false)
        AppLog.info("update", "installing v\(info.version) at quit")
    }

    private func rememberInstall(_ info: UpdateInfo) {
        AppDefaults.shared.set(info.version, forKey: Self.installedVersionKey)
        AppDefaults.shared.set(info.notes, forKey: Self.installedNotesKey)
        AppDefaults.shared.set(info.name, forKey: Self.installedNameKey)
    }

    private func noteFreshInstall(_ current: String) {
        guard AppDefaults.shared.string(forKey: Self.installedVersionKey) == current else { return }
        justUpdated = UpdateInfo(version: current, name: AppDefaults.shared.string(forKey: Self.installedNameKey) ?? "Version \(current)",
                                 notes: AppDefaults.shared.string(forKey: Self.installedNotesKey) ?? "",
                                 pageURL: URL(string: "https://github.com/\(repo)/releases/latest")!, downloadURL: nil)
        AppDefaults.shared.removeObject(forKey: Self.installedVersionKey)
        AppDefaults.shared.removeObject(forKey: Self.installedNotesKey)
        AppDefaults.shared.removeObject(forKey: Self.installedNameKey)
        try? FileManager.default.removeItem(at: stagingDir)
        AppLog.info("update", "first launch of v\(current) after a self-update")
    }

    // MARK: - User actions

    /// From the modal: install right away (staging first if needed).
    func update(_ info: UpdateInfo) {
        guard canSelfInstall, let zip = info.downloadURL else {
            NSWorkspace.shared.open(info.downloadURL ?? info.pageURL)
            available = nil
            return
        }
        if staged?.version == info.version { installNow(); return }
        install = .working("Downloading update…")
        Task {
            if staging == nil { staging = Task { await download(info, from: zip) } }
            await staging?.value
            if staged?.version == info.version {
                install = .working("Installing…")
                installNow()
            } else {
                install = .failed("Update failed. You can download it manually.")
            }
        }
    }

    func openDownload(_ info: UpdateInfo) {
        NSWorkspace.shared.open(info.downloadURL ?? info.pageURL)
        available = nil
    }

    func skip(_ info: UpdateInfo) { skippedVersion = info.version; available = nil }
    func ignoreThisTime(_ info: UpdateInfo) { snoozedThisSession.insert(info.version); available = nil }
    func dismiss() { available = nil }
    func dismissWhatsNew() { showWhatsNew = false; justUpdated = nil }

    // MARK: - Verification and the swap

    /// Unzips and confirms the update is intact, notarized, the advertised
    /// version, and from the same developer as the running app.
    nonisolated private static func unpackAndVerify(zip: URL, work: URL, oldApp: String, version: String, sha256: String?) throws -> URL {
        if let sha256 {
            let data = try Data(contentsOf: zip)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == sha256 else { throw UpdateError(message: "Download didn't match its checksum.") }
        }
        let unpack = work.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpack.path]).code == 0 else {
            throw UpdateError(message: "Couldn't unpack the update.")
        }
        guard let newApp = (try FileManager.default.contentsOfDirectory(at: unpack, includingPropertiesForKeys: nil))
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError(message: "Update didn't contain an app.") }

        let plist = newApp.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: plist), let v = dict["CFBundleShortVersionString"] as? String,
           UpdateStrategy.compare(UpdateStrategy.normalize(v), version) != 0 {
            throw UpdateError(message: "Update is version \(v), not \(version).")
        }
        guard run("/usr/bin/codesign", ["--verify", "--strict", "--deep", newApp.path]).code == 0 else {
            throw UpdateError(message: "Update failed its signature check.")
        }
        guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path]).code == 0 else {
            throw UpdateError(message: "Update isn't notarized.")
        }
        let newTeam = teamID(newApp.path)
        if let oldTeam = teamID(oldApp), let newTeam, oldTeam != newTeam {
            throw UpdateError(message: "Update is signed by a different developer.")
        }
        try? FileManager.default.removeItem(at: zip)
        return newApp
    }

    /// A detached shell helper that outlives this process: waits for it to exit,
    /// keeps the old bundle as a backup, moves the new one into place, and if the
    /// new app isn't running shortly after relaunch puts the backup back.
    nonisolated private static func relaunchHelper(pid: Int32, oldApp: String, newApp: String, work: URL, relaunch: Bool) throws {
        let script = """
        #!/bin/sh
        OLD="\(oldApp)"; NEW="\(newApp)"; BACKUP="\(oldApp).previous"; WORK="\(work.path)"
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$BACKUP"
        /bin/mv "$OLD" "$BACKUP" || exit 1
        if /bin/mv "$NEW" "$OLD" 2>/dev/null || /usr/bin/ditto "$NEW" "$OLD"; then
          /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
          if [ "\(relaunch ? 1 : 0)" = "1" ]; then
            /usr/bin/open "$OLD"
            /bin/sleep 20
            if /usr/bin/pgrep -f "$OLD/Contents/MacOS/" >/dev/null; then
              /bin/rm -rf "$BACKUP"
            else
              /bin/rm -rf "$OLD"; /bin/mv "$BACKUP" "$OLD"; /usr/bin/open "$OLD"
            fi
          else
            /bin/rm -rf "$BACKUP"
          fi
        else
          /bin/rm -rf "$OLD"; /bin/mv "$BACKUP" "$OLD"
          if [ "\(relaunch ? 1 : 0)" = "1" ]; then /usr/bin/open "$OLD"; fi
        fi
        /bin/rm -rf "$WORK"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("xeneon-apply-\(pid).sh")
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

    // MARK: - Demo

    /// Sample states for previewing (XENEON_UPDATE_DEMO = 1 | ready | updated).
    func demo(_ mode: String) {
        let info = UpdateInfo(
            version: "9.9.9", name: "Preview",
            notes: """
            ## ✨ New
            - **Web tab** — open and save any site right on the Edge, with favicons.
            - **Fullscreen mode** — every page can fill the panel; the browser goes fully immersive.

            ## 🛠 Improved
            - The phone remote can now push a URL straight to the Edge.

            ## 🐞 Fixed
            - The browser's Stop and Retry buttons now behave correctly.
            """,
            pageURL: URL(string: "https://github.com/\(repo)/releases/latest")!, downloadURL: nil)
        switch mode {
        case "ready": staged = info; showReadyNotice = true
        case "updated": justUpdated = info
        default: available = info
        }
    }

    static func normalize(_ tag: String) -> String { UpdateStrategy.normalize(tag) }
    static func compare(_ a: String, _ b: String) -> Int { UpdateStrategy.compare(a, b) }
}
