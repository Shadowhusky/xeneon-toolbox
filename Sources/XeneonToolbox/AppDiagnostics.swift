import Foundation
import os

/// Structured logging: every line goes to the unified log (Console.app /
/// `log stream --predicate 'subsystem == "com.shadowhusky.xeneon-toolbox"'`)
/// AND to a plain-text rolling file the user can read or attach to a report:
/// ~/.config/xeneon-toolbox/app.log (rotates to app.log.old at ~1 MB).
enum AppLog {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/xeneon-toolbox")
    static var fileURL: URL { dir.appendingPathComponent("app.log") }

    private static let osLog = Logger(subsystem: "com.shadowhusky.xeneon-toolbox", category: "app")
    private static let queue = DispatchQueue(label: "com.shadowhusky.xeneon.applog", qos: .utility)
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ tag: String, _ message: String) {
        osLog.info("[\(tag, privacy: .public)] \(message, privacy: .public)")
        append("[\(stamp.string(from: Date()))] [\(tag)] \(message)")
    }

    static func error(_ tag: String, _ message: String) {
        osLog.error("[\(tag, privacy: .public)] ERROR \(message, privacy: .public)")
        append("[\(stamp.string(from: Date()))] [\(tag)] ERROR \(message)")
    }

    private static func append(_ line: String) {
        queue.async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = fileURL
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
                let old = dir.appendingPathComponent("app.log.old")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: url, to: old)
            }
            let data = Data((line + "\n").utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                h.seekToEndOfFile()
                h.write(data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// Crash reporting without dependencies: catches uncaught Objective-C exceptions
/// and fatal signals (SIGSEGV, SIGABRT, …), writes the reason + full stack trace
/// to ~/.config/xeneon-toolbox/crash-<timestamp>.log, then lets the default
/// handler run so macOS still produces its own .ips report. A session marker
/// also detects "the app was gone without a clean quit" on the next launch.
struct CrashReport: Equatable {
    let file: URL
    let body: String
}

enum CrashReporter {
    private static var marker: URL { AppLog.dir.appendingPathComponent("session.active") }

    static func install() {
        try? FileManager.default.createDirectory(at: AppLog.dir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: marker.path) {
            AppLog.error("lifecycle", "previous session ended WITHOUT a clean quit (crash or force kill) — check crash-*.log and macOS DiagnosticReports")
        }
        try? Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: marker)

        NSSetUncaughtExceptionHandler { ex in
            CrashReporter.writeCrash(
                "Uncaught exception: \(ex.name.rawValue)\nReason: \(ex.reason ?? "-")",
                stack: ex.callStackSymbols)
        }

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                CrashReporter.writeCrash(
                    "Fatal signal \(s) (\(String(cString: strsignal(s))))",
                    stack: Thread.callStackSymbols)
                signal(s, SIG_DFL)   // fall through to the default handler → .ips report
                raise(s)
            }
        }
    }

    static func markCleanExit() {
        try? FileManager.default.removeItem(at: marker)
    }

    /// The newest crash log the user hasn't been asked about yet — the launch
    /// path uses this to offer a one-tap "send the report" prompt.
    static func pendingReport() -> CrashReport? {
        let handled = AppDefaults.shared.string(forKey: "crash.lastHandled")
        guard let files = try? FileManager.default.contentsOfDirectory(at: AppLog.dir, includingPropertiesForKeys: nil) else { return nil }
        let newest = files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
        guard let newest, newest.lastPathComponent != handled,
              let body = try? String(contentsOf: newest, encoding: .utf8) else { return nil }
        return CrashReport(file: newest, body: body)
    }

    static func markHandled(_ report: CrashReport) {
        AppDefaults.shared.set(report.file.lastPathComponent, forKey: "crash.lastHandled")
    }

    /// A prefilled GitHub issue with the crash content (trimmed to fit a URL).
    static func githubIssueURL(for report: CrashReport) -> URL? {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let text = "macOS \(os)\n\n```\n\(report.body.prefix(5_000))\n```"
        var c = URLComponents(string: "https://github.com/Shadowhusky/xeneon-toolbox/issues/new")!
        c.queryItems = [
            URLQueryItem(name: "title", value: "Crash report"),
            URLQueryItem(name: "body", value: text),
        ]
        return c.url
    }

    private static func writeCrash(_ headline: String, stack: [String]) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = AppLog.dir.appendingPathComponent("crash-\(f.string(from: Date())).log")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let body = """
        Xeneon Toolbox \(version) crashed at \(Date())
        \(headline)

        \(stack.joined(separator: "\n"))
        """
        try? Data(body.utf8).write(to: url)
    }
}
