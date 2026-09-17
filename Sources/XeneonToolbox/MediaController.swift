import AppKit
import Combine

/// A snapshot of the currently playing track.
struct NowPlaying: Equatable {
    enum Source { case spotify, music }
    var source: Source
    var title: String
    var artist: String
    var album: String
    var duration: Double      // seconds (0 if unknown)
    var elapsed: Double       // seconds, measured at `asOf`
    var rate: Double          // 0 = paused, 1 = playing
    var asOf: Date
    var artworkURL: String?
    var artwork: NSImage?

    var isPlaying: Bool { rate > 0 }

    func elapsedNow(_ now: Date = Date()) -> Double {
        guard rate > 0 else { return elapsed }
        let t = elapsed + now.timeIntervalSince(asOf) * rate
        return duration > 0 ? min(duration, max(0, t)) : max(0, t)
    }

    static func == (a: NowPlaying, b: NowPlaying) -> Bool {
        a.source == b.source && a.title == b.title && a.artist == b.artist &&
        a.album == b.album && a.duration == b.duration && a.rate == b.rate && (a.artwork === b.artwork)
    }
}

/// Reads and controls the currently playing track via AppleScript, targeting
/// Spotify and Apple Music (the system-wide MediaRemote API is locked to
/// Apple-entitled binaries on macOS 15.4+, so it isn't usable from a notarized
/// third-party app). Controlling another app needs the one-time Automation
/// permission macOS prompts for on first use.
///
/// Event-driven: both players broadcast a distributed notification on every
/// track / play-state change, so the (subprocess-spawning) read runs only then,
/// plus a slow safety poll while a player is running. The old 2 s poll spawned
/// `osascript` 30 times a minute for nothing.
@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    /// True once we've successfully read a track at least once (so the UI knows
    /// scripting is permitted and a player is present).
    @Published private(set) var available = false

    private var pollTimer: Timer?
    private var artwork: (url: String, image: NSImage)?
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var started = false
    private var readInFlight = false
    private var readAgain = false

    private static let spotifyBundle = "com.spotify.client"
    private static let musicBundle = "com.apple.Music"
    private static let playerNotifications = ["com.spotify.client.PlaybackStateChanged",
                                              "com.apple.Music.playerInfo",
                                              "com.apple.iTunes.playerInfo"]
    private static let safetyPoll: TimeInterval = 20

    func start() {
        guard !started else { return }
        started = true
        let dnc = DistributedNotificationCenter.default()
        distributedObservers = Self.playerNotifications.map { name in
            dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                      id == Self.spotifyBundle || id == Self.musicBundle else { return }
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func stop() {
        guard started else { return }
        started = false
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.removeAll()
        workspaceObservers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        // Only script an app that's actually running, so we never launch one.
        let bundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let spotify = bundles.contains(Self.spotifyBundle)
        let music = bundles.contains(Self.musicBundle)
        updateSafetyPoll(playerRunning: spotify || music)
        guard spotify || music else {
            if nowPlaying != nil { nowPlaying = nil }
            return
        }
        // Coalesce: a burst of notifications (track change = several) becomes one
        // read now and one after it lands.
        guard !readInFlight else { readAgain = true; return }
        readInFlight = true
        Task.detached(priority: .utility) {
            let np = (spotify ? Self.read(.spotify) : nil) ?? (music ? Self.read(.music) : nil)
            await MainActor.run { self.finishRead(np) }
        }
    }

    private func finishRead(_ np: NowPlaying?) {
        readInFlight = false
        apply(np)
        if readAgain { readAgain = false; refresh() }
    }

    private func updateSafetyPoll(playerRunning: Bool) {
        if playerRunning {
            guard pollTimer == nil else { return }
            let t = Timer(timeInterval: Self.safetyPoll, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
        } else if let t = pollTimer {
            t.invalidate()
            pollTimer = nil
        }
    }

    private func apply(_ np: NowPlaying?) {
        guard var np else {
            if nowPlaying != nil { nowPlaying = nil }
            return
        }
        if !available { available = true }
        // Reuse cached artwork for the same URL; fetch a new one in the background.
        if let url = np.artworkURL {
            if artwork?.url == url { np.artwork = artwork?.image }
            else { fetchArtwork(url) }
        }
        // Publish only a real change; the safety poll mostly confirms what's shown.
        if let cur = nowPlaying, cur == np, abs(cur.elapsedNow() - np.elapsedNow()) < 2 { return }
        nowPlaying = np
    }

    private func fetchArtwork(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let img = NSImage(data: data) else { return }
            await MainActor.run {
                self.artwork = (urlString, img)
                if self.nowPlaying?.artworkURL == urlString { self.nowPlaying?.artwork = img }
            }
        }
    }

    // MARK: - Transport

    func togglePlayPause() { control("playpause") }
    func next() { control("next track") }
    func previous() { control("previous track") }

    func seek(to seconds: Double) {
        guard let source = nowPlaying?.source else { return }
        // Optimistically move the bar now so it doesn't flick back to the old
        // position while AppleScript applies the seek and the next read lands.
        if var np = nowPlaying { np.elapsed = seconds; np.asOf = Date(); nowPlaying = np }
        let app = source == .music ? "Music" : "Spotify"
        Task.detached(priority: .userInitiated) {
            Self.runScript("tell application \"\(app)\" to set player position to \(Int(seconds))")
            await MainActor.run { self.refreshSoon() }
        }
    }

    private func control(_ verb: String) {
        guard let source = nowPlaying?.source else { return }
        let app = source == .music ? "Music" : "Spotify"
        Task.detached(priority: .userInitiated) {
            Self.runScript("tell application \"\(app)\" to \(verb)")
            await MainActor.run { self.refreshSoon() }
        }
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - AppleScript

    nonisolated private static func read(_ source: NowPlaying.Source) -> NowPlaying? {
        let app = source == .music ? "Music" : "Spotify"
        // Newline-delimited fields (track text can't contain newlines): state,
        // name, artist, album, position(s), duration(s), artwork url.
        let durationExpr = source == .music ? "(duration of t)" : "((duration of t) / 1000)"
        let artworkExpr = source == .music ? "\"\"" : "(artwork url of t)"
        let script = """
        tell application "\(app)"
          if player state is stopped then return "stopped"
          set t to current track
          return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((player position) as text) & linefeed & (\(durationExpr) as text) & linefeed & \(artworkExpr)
        end tell
        """
        guard let out = runScript(script), out != "stopped" else { return nil }
        let f = out.components(separatedBy: "\n")
        guard f.count >= 6, !f[1].isEmpty else { return nil }
        return NowPlaying(
            source: source,
            title: f[1],
            artist: f[2],
            album: f[3],
            duration: Double(f[5]) ?? 0,
            elapsed: Double(f[4]) ?? 0,
            rate: f[0].hasPrefix("playing") ? 1 : 0,
            asOf: Date(),
            artworkURL: f.count >= 7 && !f[6].isEmpty ? f[6] : nil,
            artwork: nil)
    }

    @discardableResult
    nonisolated private static func runScript(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (p.terminationStatus == 0) ? s : nil
    }
}
