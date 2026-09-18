import AppKit
import Foundation

/// An app that could be quit to give memory and CPU back.
struct BoostCandidate: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let rssMB: Double
    let cpu: Double
    let isFrontmost: Bool
    /// Heavy and in the background: the ones Boost pre-selects.
    let suggested: Bool
    var id: pid_t { pid }

    static func == (a: BoostCandidate, b: BoostCandidate) -> Bool { a.pid == b.pid && a.rssMB == b.rssMB && a.cpu == b.cpu }
}

/// Finds the apps worth quitting and quits them gracefully. Honest by design:
/// macOS manages memory well on its own, so the only thing that reliably makes
/// a Mac feel faster is closing heavy apps you're not using. Nothing is force
/// killed; an app with unsaved work asks before it closes, like it always does.
@MainActor
final class BoostScanner: ObservableObject {
    @Published private(set) var candidates: [BoostCandidate] = []
    @Published private(set) var scanning = false
    @Published var selected: Set<pid_t> = []
    @Published private(set) var lastFreedMB: Double?

    /// Bundle ids that are never suggested: the Toolbox, Finder, and whatever is playing music.
    var protectedBundleIDs: Set<String> = ["com.apple.finder"]

    func scan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        let me = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let myBundle = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
                && !(myBundle != nil && $0.bundleIdentifier == myBundle) && $0.localizedName != "Xeneon Toolbox"
        }
        let stats = await Task.detached(priority: .userInitiated) { Self.processStats() }.value
        let protected = protectedBundleIDs
        var out: [BoostCandidate] = []
        for app in apps {
            let pid = app.processIdentifier
            let s = stats[pid] ?? (cpu: 0, rssMB: 0)
            let isFront = pid == front
            let heavy = s.rssMB >= 400 || s.cpu >= 30
            let safe = !isFront && !(app.bundleIdentifier.map(protected.contains) ?? false)
            out.append(BoostCandidate(pid: pid, name: app.localizedName ?? "App", icon: app.icon,
                                      rssMB: s.rssMB, cpu: s.cpu, isFrontmost: isFront, suggested: heavy && safe))
        }
        out.sort { $0.rssMB > $1.rssMB }
        candidates = out
        selected = Set(out.filter(\.suggested).map(\.id))
    }

    /// Asks each selected app to quit (the same as ⌘Q), then re-scans.
    func quitSelected() async {
        let chosen = candidates.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        var freed = 0.0
        for c in chosen {
            if let app = NSRunningApplication(processIdentifier: c.pid), app.terminate() { freed += c.rssMB }
        }
        AppLog.info("boost", "asked \(chosen.count) app(s) to quit, ~\(Int(freed)) MB")
        try? await Task.sleep(for: .seconds(2))
        lastFreedMB = freed
        await scan()
    }

    /// CPU percent and resident memory per pid from one `ps` call.
    nonisolated private static func processStats() -> [pid_t: (cpu: Double, rssMB: Double)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pid,pcpu,rss"]
        let pipe = Pipe(); p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [:] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var stats: [pid_t: (cpu: Double, rssMB: Double)] = [:]
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = pid_t(parts[0]), let cpu = Double(parts[1]), let rssKB = Double(parts[2]) else { continue }
            stats[pid] = (cpu, rssKB / 1024)
        }
        return stats
    }
}
