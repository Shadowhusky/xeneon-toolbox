import Foundation

/// How the app treats a newer release.
public enum UpdatePolicy: String, CaseIterable, Sendable {
    /// Download and verify in the background, install at a quiet moment.
    case automatic
    /// Show the release and let the user decide.
    case notify
    /// Only look when asked from Settings.
    case off
}

/// The pure decisions behind the updater, kept here so they can be tested.
public enum UpdateStrategy {
    public static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    /// Numeric compare of dotted versions: 1 if a > b, -1 if a < b, 0 if equal.
    public static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// A staged update may install when nobody has touched the panel for a while
    /// and nothing is mid-flight. The full UI gets a longer grace period than
    /// the ambient or sleeping screen, because a relaunch there is visible.
    public static func isQuietMoment(idleSeconds: Double, interacting: Bool, fullUI: Bool) -> Bool {
        guard !interacting else { return false }
        return idleSeconds >= (fullUI ? 30 * 60 : 10 * 60)
    }

    /// Check cadence with ±10% jitter so installs don't all hit the API at once.
    public static func nextCheckDelay(base: TimeInterval, random: Double) -> TimeInterval {
        base * (0.9 + 0.2 * min(max(random, 0), 1))
    }
}
