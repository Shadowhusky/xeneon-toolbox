import Foundation

/// macOS output volume via AppleScript's StandardAdditions (`set volume` /
/// `get volume settings`) — a system command, so no Automation permission is
/// needed. Returns nil when the current output device has no software volume
/// (e.g. some HDMI/optical/USB outputs report "missing value").
enum SystemVolume {
    static func level() -> Int? {
        guard let s = run("output volume of (get volume settings)"), let v = Int(s) else { return nil }
        return v
    }

    static func isMuted() -> Bool { run("output muted of (get volume settings)") == "true" }

    static func set(_ value: Int) { _ = run("set volume output volume \(max(0, min(100, value)))") }

    static func setMuted(_ muted: Bool) { _ = run("set volume \(muted ? "with" : "without") output muted") }

    @discardableResult
    private static func run(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
