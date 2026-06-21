import Foundation

/// Controls the Edge's LED backlight over DDC/CI (via the bundled `m1ddc` helper).
///
/// The Edge is an LCD: its backlight is always on, so dark pixels save no power.
/// Lowering the backlight (luminance) is the only software way to actually save
/// power / reduce heat / spare the backlight. DDC has no portable "power off", so
/// luminance 0 (panel minimum) is the lowest we can go from software.
enum Backlight {
    static var helperPath: String? {
        if let bundled = Bundle.main.path(forResource: "m1ddc", ofType: nil) { return bundled }
        for p in ["/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static var isAvailable: Bool { helperPath != nil && edgeDisplay() != nil }

    /// DDC is slow (~50–200 ms) — never call these on the main thread directly.
    private static func run(_ args: [String]) -> String? {
        guard let path = helperPath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 ? s : nil
    }

    private static var cachedEdge: String?
    /// m1ddc display number for the Edge, matched by name (robust to ordering).
    static func edgeDisplay() -> String? {
        if let c = cachedEdge { return c }
        guard let list = run(["display", "list"]) else { return nil }
        for line in list.split(separator: "\n") where line.uppercased().contains("XENEON") {
            if let lb = line.firstIndex(of: "["), let rb = line.firstIndex(of: "]"), lb < rb {
                cachedEdge = String(line[line.index(after: lb)..<rb])
                return cachedEdge
            }
        }
        return nil
    }

    static func getBrightness() -> Int? {
        guard let d = edgeDisplay(), let s = run(["display", d, "get", "luminance"]) else { return nil }
        return Int(s)
    }

    @discardableResult
    static func setBrightness(_ value: Int) -> Bool {
        guard let d = edgeDisplay() else { return false }
        return run(["display", d, "set", "luminance", "\(max(0, min(100, value)))"]) != nil
    }
}
