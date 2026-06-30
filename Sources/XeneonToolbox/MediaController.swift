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
@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    /// True once we've successfully read a track at least once (so the UI knows
    /// scripting is permitted and a player is present).
    @Published private(set) var available = false

    private var pollTimer: Timer?
    private var artwork: (url: String, image: NSImage)?

    private static let spotifyBundle = "com.spotify.client"
    private static let musicBundle = "com.apple.Music"

    func start() {
        guard pollTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        refresh()
    }

    func refresh() {
        // Only script an app that's actually running, so we never launch one.
        let bundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let spotify = bundles.contains(Self.spotifyBundle)
        let music = bundles.contains(Self.musicBundle)
        guard spotify || music else { nowPlaying = nil; return }
        Task.detached(priority: .utility) {
            let np = (spotify ? Self.read(.spotify) : nil) ?? (music ? Self.read(.music) : nil)
            await MainActor.run { self.apply(np) }
        }
    }

    private func apply(_ np: NowPlaying?) {
        guard var np else { nowPlaying = nil; return }
        available = true
        // Reuse cached artwork for the same URL; fetch a new one in the background.
        if let url = np.artworkURL {
            if artwork?.url == url { np.artwork = artwork?.image }
            else { fetchArtwork(url) }
        }
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
        Self.runScript("tell application \"\(source == .music ? "Music" : "Spotify")\" to set player position to \(Int(seconds))")
        refreshSoon()
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
