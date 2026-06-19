import Foundation
import AppKit
import SwiftOpenAI
import ToolboxKit

/// An agentic assistant: streams replies, accepts images, and can drive the
/// toolbox via tools (it knows the app's tabs, stats, and controls).
struct ProcRow: Identifiable {
    let id = UUID()
    let name: String
    let cpu: Double   // percent
    let mem: Double   // percent
}

struct CardRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

/// A visual artifact the agent can render into the transcript (generative UI).
enum AgentCard {
    case processes([ProcRow])
    case generic(title: String, rows: [CardRow])
    case chart(title: String, points: [ChartPoint], line: Bool)
    case table(title: String, headers: [String], rows: [[String]])
    case image(Data)
}

/// One step in the agent's tool activity — shown live (working) then completed.
struct ToolStep: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool
}

/// Persisted conversation (only user/assistant text; tool activity is ephemeral).
struct StoredConversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var messages: [StoredMessage]
    var updated: Date
    var autoTitled: Bool? = nil
}

struct StoredMessage: Codable {
    let role: String   // "user" | "assistant"
    let text: String
}

@MainActor
final class AgentController: ObservableObject {
    struct Turn: Identifiable {
        let id = UUID()
        var role: String          // "user" | "assistant" | "tools" | "error" | "card"
        var text: String
        var imageThumb: Bool = false
        var card: AgentCard? = nil
        var steps: [ToolStep] = []  // for role "tools": live, collapsible activity
    }

    enum ConfirmDecision { case approve, always, deny }

    struct PendingAction: Identifiable {
        let id = UUID()
        let tool: String
        let title: String
        let detail: String
        let dangerous: Bool   // dangerous actions can't be "always allowed"
    }

    @Published var turns: [Turn] = []
    @Published var busy = false
    @Published var pending: PendingAction?
    private var confirmContinuation: CheckedContinuation<Bool, Never>?
    private var alwaysAllowed: Set<String> = []
    private var task: Task<Void, Never>?

    /// Suspends the agent loop until the user decides. Auto-approves tools the
    /// user previously chose to always allow.
    private func requestApproval(tool: String, dangerous: Bool, title: String, detail: String) async -> Bool {
        if alwaysAllowed.contains(tool) { return true }
        return await withCheckedContinuation { cont in
            confirmContinuation = cont
            pending = PendingAction(tool: tool, title: title, detail: detail, dangerous: dangerous)
        }
    }

    func resolve(_ decision: ConfirmDecision) {
        if decision == .always, let tool = pending?.tool { alwaysAllowed.insert(tool) }
        pending = nil
        confirmContinuation?.resume(returning: decision != .deny)
        confirmContinuation = nil
    }

    @Published var conversations: [StoredConversation] = []
    @Published private(set) var activeID = UUID()

    private var config: ChatConfig
    private weak var app: ToolboxModel?
    private var history: [SwiftOpenAI.ChatCompletionParameters.Message] = []

    private struct StoredFile: Codable { var conversations: [StoredConversation]; var activeID: UUID }
    private static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox/conversations.json")
    }

    init(config: ChatConfig, app: ToolboxModel?) {
        self.config = config
        self.app = app
        loadStore()
    }

    func update(config: ChatConfig) { self.config = config }

    // MARK: - Conversations

    func newConversation() {
        saveActive()
        let c = StoredConversation(id: UUID(), title: "New chat", messages: [], updated: Date())
        conversations.insert(c, at: 0)
        activeID = c.id
        turns = []; history = []
        writeStore()
    }

    func select(_ id: UUID) {
        guard id != activeID else { return }
        saveActive()
        activeID = id
        loadActiveTurns()
        writeStore()
    }

    func clearAll() {
        cancel()
        let c = StoredConversation(id: UUID(), title: "New chat", messages: [], updated: Date())
        conversations = [c]
        activeID = c.id
        turns = []; history = []
        writeStore()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeID == id {
            if let first = conversations.first { activeID = first.id; loadActiveTurns() }
            else { newConversation(); return }
        }
        writeStore()
    }

    private func loadStore() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let file = try? JSONDecoder().decode(StoredFile.self, from: data), !file.conversations.isEmpty {
            conversations = file.conversations.sorted { $0.updated > $1.updated }
            activeID = conversations.contains { $0.id == file.activeID } ? file.activeID : conversations[0].id
            loadActiveTurns()
        } else {
            let c = StoredConversation(id: UUID(), title: "New chat", messages: [], updated: Date())
            conversations = [c]; activeID = c.id
        }
    }

    private func loadActiveTurns() {
        guard let c = conversations.first(where: { $0.id == activeID }) else { turns = []; history = []; return }
        turns = c.messages.map { Turn(role: $0.role, text: $0.text) }
        history = c.messages.map { .init(role: $0.role == "user" ? .user : .assistant, content: .text($0.text)) }
    }

    private func saveActive() {
        guard let i = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        conversations[i].messages = turns.compactMap {
            ($0.role == "user" || $0.role == "assistant") && !$0.text.isEmpty ? StoredMessage(role: $0.role, text: $0.text) : nil
        }
        if let firstUser = turns.first(where: { $0.role == "user" })?.text, conversations[i].title == "New chat" {
            conversations[i].title = String(firstUser.prefix(42))
        }
        conversations[i].updated = Date()
    }

    /// After the first exchange, ask the model for a short title for the chat.
    private func maybeAutoTitle() {
        guard let i = conversations.firstIndex(where: { $0.id == activeID }),
              !(conversations[i].autoTitled ?? false),
              conversations[i].messages.contains(where: { $0.role == "assistant" }),
              conversations[i].messages.contains(where: { $0.role == "user" }) else { return }
        conversations[i].autoTitled = true
        let convID = activeID
        let context = conversations[i].messages.prefix(4).map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        Task {
            let title = await generateTitle(context)
            guard !title.isEmpty, let j = conversations.firstIndex(where: { $0.id == convID }) else { return }
            conversations[j].title = title
            writeStore()
        }
    }

    private func generateTitle(_ context: String) async -> String {
        let params = ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text("Reply with ONLY a 3–5 word title for the conversation. No quotes, no punctuation, no preamble.")),
                .init(role: .user, content: .text(context)),
            ],
            model: .custom(config.model))
        guard let result = try? await service.startChat(parameters: params),
              let text = result.choices?.first?.message?.content else { return "" }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\".'")))
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(48).description
    }

    private func writeStore() {
        saveActive()
        try? FileManager.default.createDirectory(at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(StoredFile(conversations: conversations, activeID: activeID)) {
            try? data.write(to: Self.storeURL)
        }
    }

    private var service: OpenAIService {
        // SwiftOpenAI appends /v1/...; pass the host without a trailing /v1.
        var host = config.baseURL
        if host.hasSuffix("/v1") { host = String(host.dropLast(3)) }
        if host.hasSuffix("/") { host = String(host.dropLast()) }
        return OpenAIServiceFactory.service(apiKey: .apiKey(config.apiKey ?? ""), baseURL: host)
    }

    // MARK: - Tools

    private func tools() -> [ChatCompletionParameters.Tool] {
        func tool(_ name: String, _ desc: String, _ props: [String: JSONSchema] = [:], required: [String] = []) -> ChatCompletionParameters.Tool {
            .init(function: .init(name: name, strict: nil, description: desc,
                                  parameters: .init(type: .object, properties: props, required: required)))
        }
        return [
            // App awareness + control
            tool("get_app_state", "Get the current tab, touch status, and live system stats (CPU, memory, network, disk, uptime)."),
            tool("navigate", "Switch to a tab in the toolbox.",
                 ["tab": .init(type: .string, enum: ["dashboard", "clock", "games", "assistant"])], required: ["tab"]),
            tool("set_touch", "Turn the Edge touchscreen driver on or off.",
                 ["enabled": .init(type: .boolean)], required: ["enabled"]),
            tool("open_game", "Open the Games tab and select a game.",
                 ["game": .init(type: .string, enum: ["shanhai", "rhythm"])], required: ["game"]),
            tool("show_top_processes", "Show the top CPU-using processes as a visual card on screen.",
                 ["count": .init(type: .integer)]),
            tool("show_card", "Display any data as a touch-friendly card on screen. Give a title and items as \"Label: value\" strings.",
                 ["title": .init(type: .string), "items": .init(type: .array, items: .init(type: .string))],
                 required: ["title", "items"]),
            tool("show_chart", "Visualize numeric data as a bar or line chart. Items are \"label: number\" strings; type is 'bar' or 'line'.",
                 ["title": .init(type: .string), "items": .init(type: .array, items: .init(type: .string)),
                  "type": .init(type: .string, enum: ["bar", "line"])],
                 required: ["title", "items"]),
            tool("show_table", "Display tabular data as a touch-friendly table (good for comparisons with multiple columns). Provide column headers, and rows where each row string separates cells with ' | '.",
                 ["title": .init(type: .string), "headers": .init(type: .array, items: .init(type: .string)),
                  "rows": .init(type: .array, items: .init(type: .string))],
                 required: ["headers", "rows"]),
            tool("generate_image", "Generate an image from a text prompt and show it (requires an OpenAI API key in settings).",
                 ["prompt": .init(type: .string)], required: ["prompt"]),
            // Web
            tool("web_search", "Search the web and return top results (titles, snippets, links).",
                 ["query": .init(type: .string)], required: ["query"]),
            tool("fetch_url", "Fetch a web page and return its readable text.",
                 ["url": .init(type: .string)], required: ["url"]),
            // Files
            tool("list_dir", "List files in a directory (supports ~).",
                 ["path": .init(type: .string)], required: ["path"]),
            tool("read_file", "Read a text file (supports ~). Truncated to 6000 chars.",
                 ["path": .init(type: .string)], required: ["path"]),
            tool("write_file", "Write text to a file (supports ~), creating or overwriting it. Asks the user to confirm.",
                 ["path": .init(type: .string), "content": .init(type: .string)], required: ["path", "content"]),
            // System
            tool("run_command", "Run a shell command and return its output. Asks the user to confirm first.",
                 ["command": .init(type: .string)], required: ["command"]),
            tool("get_clipboard", "Read the current macOS clipboard text."),
            tool("set_clipboard", "Put text on the macOS clipboard.",
                 ["text": .init(type: .string)], required: ["text"]),
            tool("open_url", "Open a URL in the default browser.",
                 ["url": .init(type: .string)], required: ["url"]),
            tool("current_datetime", "Get the current local date and time."),
            tool("set_volume", "Set the Mac output volume (0–100).",
                 ["level": .init(type: .integer)], required: ["level"]),
            tool("get_volume", "Get the current Mac output volume (0–100)."),
            tool("media_control", "Control media playback for any player: play/pause, next, or previous track.",
                 ["action": .init(type: .string, enum: ["play_pause", "next", "previous"])], required: ["action"]),
            tool("now_playing", "Get the track currently playing in Spotify or Music."),
            tool("open_app", "Open or focus a Mac application by name (e.g. Safari, Spotify, Notes).",
                 ["name": .init(type: .string)], required: ["name"]),
        ]
    }

    private func runTool(_ name: String, _ args: [String: Any]) async -> String {
        switch name {
        case "navigate":
            guard let app, let t = args["tab"] as? String, let r = AppRoute(rawValue: t) else { return "Unknown tab." }
            app.route = r; return "Opened \(r.title)."
        case "set_touch":
            guard let app else { return "App unavailable." }
            let on = args["enabled"] as? Bool ?? false
            on ? app.startTouch() : app.stopTouch()
            return "Touch \(on ? "enabled" : "disabled")."
        case "open_game":
            guard let app else { return "App unavailable." }
            let g = (args["game"] as? String) == "rhythm" ? "rhythm" : "shanhai"
            app.gamePref = g; app.route = .games
            return "Opened \(g == "rhythm" ? "Rhythm Plus" : "山海残卷")."
        case "get_app_state":
            guard let app else { return "App unavailable." }
            let s = app.metrics.snap
            var out = "tab=\(app.route.rawValue); touch=\(app.touchStatus == .active ? "active" : app.touchOn ? "searching" : "off"); cpu=\(Int(s.cpu*100))%; mem=\(Fmt.gb(s.memUsed))/\(Fmt.gb(s.memTotal))GB; diskFree=\(Fmt.gb(s.diskFree))GB; uptime=\(Fmt.uptime(s.uptime))"
            if let b = s.battery { out += "; battery=\(Int(b.level*100))%\(b.charging ? " (charging)" : "")" }
            if let w = app.weather.weather { out += "; weather=\(w.displayTemp) in \(w.city)" }
            return out
        case "show_top_processes":
            let n = (args["count"] as? Int) ?? 6
            let rows = topProcesses(n)
            turns.append(Turn(role: "card", text: "", card: .processes(rows)))
            return "Displayed a card with the top \(rows.count) processes: " + rows.map { "\($0.name) \(Int($0.cpu))%" }.joined(separator: ", ")
        case "show_card":
            let title = (args["title"] as? String) ?? "Info"
            let items = (args["items"] as? [Any])?.compactMap { $0 as? String } ?? []
            let rows = items.map { line -> CardRow in
                if let r = line.range(of: ":") {
                    return CardRow(label: String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces),
                                   value: String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces))
                }
                return CardRow(label: line, value: "")
            }
            turns.append(Turn(role: "card", text: "", card: .generic(title: title, rows: rows)))
            return "Displayed a card titled \(title) with \(rows.count) items."
        case "show_chart":
            let title = (args["title"] as? String) ?? "Chart"
            let isLine = (args["type"] as? String) == "line"
            let items = (args["items"] as? [Any])?.compactMap { $0 as? String } ?? []
            let points: [ChartPoint] = items.compactMap { s in
                guard let r = s.range(of: ":") else { return nil }
                let label = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let num = String(s[r.upperBound...]).filter { "0123456789.-".contains($0) }
                guard let v = Double(num) else { return nil }
                return ChartPoint(label: label, value: v)
            }
            guard !points.isEmpty else { return "No numeric data to chart." }
            turns.append(Turn(role: "card", text: "", card: .chart(title: title, points: points, line: isLine)))
            return "Displayed a \(isLine ? "line" : "bar") chart titled \(title) with \(points.count) points."
        case "show_table":
            let title = (args["title"] as? String) ?? "Table"
            let headers = (args["headers"] as? [Any])?.compactMap { $0 as? String } ?? []
            let rawRows = (args["rows"] as? [Any])?.compactMap { $0 as? String } ?? []
            let rows = rawRows.map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
            guard !headers.isEmpty, !rows.isEmpty else { return "No table data to show." }
            turns.append(Turn(role: "card", text: "", card: .table(title: title, headers: headers, rows: rows)))
            return "Displayed a table titled \(title) with \(rows.count) rows and \(headers.count) columns."
        case "generate_image":
            return await generateImage((args["prompt"] as? String) ?? "")
        case "web_search":
            return await webSearch((args["query"] as? String) ?? "")
        case "fetch_url":
            return await fetchURL((args["url"] as? String) ?? "")
        case "list_dir":
            return listDir((args["path"] as? String) ?? "")
        case "read_file":
            return readFile((args["path"] as? String) ?? "")
        case "write_file":
            let path = (args["path"] as? String) ?? "", content = (args["content"] as? String) ?? ""
            let ok = await requestApproval(tool: "write_file", dangerous: false, title: "Write file",
                                           detail: "\(content.count) chars → \((path as NSString).abbreviatingWithTildeInPath)")
            return ok ? writeFile(path, content) : "Denied: file not written."
        case "run_command":
            let cmd = (args["command"] as? String) ?? ""
            let ok = await requestApproval(tool: "run_command", dangerous: true, title: "Run command", detail: cmd)
            return ok ? runCommand(cmd) : "Denied: command not run."
        case "get_clipboard":
            return NSPasteboard.general.string(forType: .string).map { "Clipboard: \($0)" } ?? "Clipboard is empty."
        case "set_clipboard":
            let text = (args["text"] as? String) ?? ""
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            return "Copied \(text.count) chars to the clipboard."
        case "open_url":
            guard let u = URL(string: (args["url"] as? String) ?? "") else { return "Invalid URL." }
            NSWorkspace.shared.open(u); return "Opened \(u.absoluteString)."
        case "current_datetime":
            let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .medium
            return f.string(from: Date())
        case "set_volume":
            let lvl = max(0, min(100, (args["level"] as? Int) ?? 50))
            _ = runOsa("set volume output volume \(lvl)")
            return "Volume set to \(lvl)."
        case "get_volume":
            let v = runOsa("output volume of (get volume settings)")
            return "Volume is \(v.isEmpty ? "unknown" : v)."
        case "media_control":
            let a = (args["action"] as? String) ?? "play_pause"
            mediaKey(a == "next" ? 17 : (a == "previous" ? 18 : 16))
            return "Sent media \(a)."
        case "now_playing":
            let r = runOsa("""
            if application "Spotify" is running then
              tell application "Spotify"
                if player state is playing then return (artist of current track) & " — " & (name of current track)
              end tell
            end if
            if application "Music" is running then
              tell application "Music"
                if player state is playing then return (artist of current track) & " — " & (name of current track)
              end tell
            end if
            return "Nothing playing"
            """)
            return r.isEmpty ? "Nothing playing." : r
        case "open_app":
            let name = (args["name"] as? String) ?? ""
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", name]
            guard (try? p.run()) != nil else { return "Couldn't open \(name)." }
            p.waitUntilExit()
            return p.terminationStatus == 0 ? "Opened \(name)." : "Couldn't find an app named \(name)."
        default:
            return "Unknown tool \(name)."
        }
    }

    private func generateImage(_ prompt: String) async -> String {
        guard let key = config.apiKey, !key.isEmpty else {
            return "Image generation needs an OpenAI API key — add one in Assistant settings."
        }
        guard !prompt.isEmpty, let url = URL(string: config.baseURL.appending("/images/generations")) else { return "Invalid prompt." }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": "gpt-image-1", "prompt": prompt, "size": "1024x1024", "n": 1])
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return "Image request failed." }
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return "Image generation failed (HTTP \(http.statusCode))."
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["data"] as? [[String: Any]])?.first else { return "No image returned." }
        if let b64 = first["b64_json"] as? String, let imgData = Data(base64Encoded: b64) {
            turns.append(Turn(role: "card", text: "", card: .image(imgData)))
            return "Generated and displayed the image."
        }
        if let s = first["url"] as? String, let iurl = URL(string: s), let (imgData, _) = try? await URLSession.shared.data(from: iurl) {
            turns.append(Turn(role: "card", text: "", card: .image(imgData)))
            return "Generated and displayed the image."
        }
        return "No image data in response."
    }

    private func mediaKey(_ key: Int32) {
        for state in [0xA, 0xB] {
            let data1 = (Int(key) << 16) | (state << 8)
            guard let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                              modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state == 0xA ? 0xA00 : 0xB00)),
                                              timestamp: 0, windowNumber: 0, context: nil,
                                              subtype: 8, data1: data1, data2: -1) else { continue }
            ev.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func runOsa(_ script: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func runCommand(_ command: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return "Failed to launch command." }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return "exit \(p.terminationStatus):\n" + String(trimmed.prefix(3000))
    }

    // MARK: - Tool implementations

    private func topProcesses(_ n: Int) -> [ProcRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pcpu,pmem,comm", "-r"]
        let pipe = Pipe(); p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var rows: [ProcRow] = []
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let cpu = Double(parts[0]), let mem = Double(parts[1]) else { continue }
            let name = parts[2...].joined(separator: " ")
            rows.append(ProcRow(name: name, cpu: cpu, mem: mem))
            if rows.count >= max(1, min(n, 12)) { break }
        }
        return rows
    }

    private func webSearch(_ query: String) async -> String {
        guard !query.isEmpty,
              let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(q)") else { return "Invalid query." }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return "Search request failed." }
        let titles = matches(in: html, pattern: "class=\"result__a\"[^>]*>(.*?)</a>").map { strip($0) }
        let snippets = matches(in: html, pattern: "class=\"result__snippet\"[^>]*>(.*?)</a>").map { strip($0) }
        let urls = matches(in: html, pattern: "class=\"result__url\"[^>]*>(.*?)</a>").map { strip($0) }
        guard !titles.isEmpty else { return "No results found." }
        var out = "Results for \"\(query)\":\n"
        for i in 0..<min(5, titles.count) {
            out += "\(i + 1). \(titles[i])"
            if i < snippets.count, !snippets[i].isEmpty { out += " — \(snippets[i])" }
            if i < urls.count, !urls[i].isEmpty { out += " [\(urls[i])]" }
            out += "\n"
        }
        return out
    }

    private func fetchURL(_ urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return "Invalid URL." }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return "Fetch failed." }
        var s = html
        // Drop non-content blocks before stripping tags (case-insensitive, dotall).
        for pat in ["(?is)<script[^>]*>.*?</script>", "(?is)<style[^>]*>.*?</style>",
                    "(?is)<head[^>]*>.*?</head>", "(?s)<!--.*?-->", "(?is)<noscript[^>]*>.*?</noscript>"] {
            s = s.replacingOccurrences(of: pat, with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = strip(s)
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*\\n\\s*\\n\\s*", with: "\n", options: .regularExpression)
        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "No readable text on the page." : String(clean.prefix(2500))
    }

    private func listDir(_ path: String) -> String {
        let p = (path as NSString).expandingTildeInPath
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: p) else { return "Cannot list \(p)." }
        return items.prefix(100).sorted().joined(separator: "\n")
    }

    private func readFile(_ path: String) -> String {
        let p = (path as NSString).expandingTildeInPath
        guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return "Cannot read \(p)." }
        return String(s.prefix(6000))
    }

    private func writeFile(_ path: String, _ content: String) -> String {
        let p = (path as NSString).expandingTildeInPath
        do { try content.write(toFile: p, atomically: true, encoding: .utf8); return "Wrote \(content.count) chars to \(p)." }
        catch { return "Write failed: \(error.localizedDescription)" }
    }

    private func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }

    private func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Send

    private var systemPrompt: String {
        """
        You are the built-in assistant inside Xeneon Toolbox, a macOS app on a Corsair Xeneon Edge — a 2560x720 ultrawide touchscreen. Tabs: Dashboard (live system telemetry), Clock (world clocks + focus timer), Games (embeds the 山海残卷 card roguelike and Rhythm Plus), and Assistant (you). "Touch" is the embedded driver that lets the user tap the Edge.

        Guidelines:
        - Answer questions directly here in the Assistant. Use web_search/fetch_url for current facts. Pick the clearest output: show_card for key/value stats or lists, show_table for multi-column comparisons, show_chart for numeric trends, generate_image for pictures. Don't force everything into one format.
        - Only use navigate or open_game when the user explicitly asks to switch tabs or open something — never navigate away just to answer a question.
        - Use get_app_state for live system info. Keep answers concise; the screen is small and wide.
        """
    }

    func send(text: String, imageDataURL: URL?) {
        guard !busy else { return }
        busy = true

        var content: [ChatCompletionParameters.Message.ContentType.MessageContent] = [.text(text)]
        if let imageDataURL { content.append(.imageUrl(.init(url: imageDataURL))) }
        let userMessage: ChatCompletionParameters.Message = imageDataURL == nil
            ? .init(role: .user, content: .text(text))
            : .init(role: .user, content: .contentArray(content))
        history.append(userMessage)
        turns.append(Turn(role: "user", text: text, imageThumb: imageDataURL != nil))
        writeStore()

        task = Task { await runLoop() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending = nil
        confirmContinuation?.resume(returning: false)
        confirmContinuation = nil
        busy = false
    }

    private var toolsTurnID: UUID?

    /// Append a live "working" step and return whether one was added.
    private func startStep(_ working: String) {
        if let id = toolsTurnID, let i = turns.firstIndex(where: { $0.id == id }) {
            turns[i].steps.append(ToolStep(text: working, done: false))
        } else {
            var t = Turn(role: "tools", text: "")
            t.steps = [ToolStep(text: working, done: false)]
            toolsTurnID = t.id
            turns.append(t)
        }
    }

    /// Mark the latest step complete with its past-tense label.
    private func endStep(_ done: String) {
        guard let id = toolsTurnID, let i = turns.firstIndex(where: { $0.id == id }),
              !turns[i].steps.isEmpty else { return }
        turns[i].steps[turns[i].steps.count - 1].text = done
        turns[i].steps[turns[i].steps.count - 1].done = true
    }

    private func host(_ v: Any?) -> String { URL(string: (v as? String) ?? "")?.host ?? "page" }

    /// (present-tense working label, past-tense done label) for a tool, or nil
    /// to show nothing (e.g. a card speaks for itself).
    private func toolLabels(_ name: String, _ args: [String: Any]) -> (String, String)? {
        switch name {
        case "navigate": let t = (args["tab"] as? String ?? "").capitalized; return ("Opening \(t)…", "Opened \(t)")
        case "set_touch": let on = (args["enabled"] as? Bool ?? false); return ("Setting touch…", "Touch \(on ? "on" : "off")")
        case "open_game": let g = (args["game"] as? String) == "rhythm" ? "Rhythm Plus" : "山海残卷"; return ("Opening \(g)…", "Opened \(g)")
        case "get_app_state": return ("Checking system…", "Checked system stats")
        case "show_top_processes": return nil
        case "show_card": return nil
        case "show_chart": return nil
        case "show_table": return nil
        case "generate_image": return ("Generating image…", "Generated an image")
        case "web_search": let q = args["query"] as? String ?? ""; return ("Searching “\(q)”…", "Searched “\(q)”")
        case "fetch_url": let h = host(args["url"]); return ("Reading \(h)…", "Read \(h)")
        case "list_dir": let p = args["path"] as? String ?? ""; return ("Listing \(p)…", "Listed \(p)")
        case "read_file": let p = args["path"] as? String ?? ""; return ("Reading \(p)…", "Read \(p)")
        case "write_file": let p = args["path"] as? String ?? ""; return ("Writing \(p)…", "Wrote \(p)")
        case "run_command": return ("Running command…", "Ran a command")
        case "get_clipboard": return ("Reading clipboard…", "Read clipboard")
        case "set_clipboard": return ("Copying…", "Set clipboard")
        case "open_url": let h = host(args["url"]); return ("Opening \(h)…", "Opened \(h) in browser")
        case "current_datetime": return ("Checking time…", "Checked the time")
        case "set_volume": return ("Setting volume…", "Set volume to \(args["level"] as? Int ?? 0)")
        case "get_volume": return ("Checking volume…", "Checked volume")
        case "media_control": return ("Controlling playback…", "Media \(args["action"] as? String ?? "")")
        case "now_playing": return ("Checking playback…", "Checked now playing")
        case "open_app": return ("Opening app…", "Opened \(args["name"] as? String ?? "app")")
        default: return (name, name)
        }
    }

    private func runLoop() async {
        defer { busy = false; writeStore(); maybeAutoTitle() }
        var assistantTurnID: UUID?
        toolsTurnID = nil

        for _ in 0..<8 {
            let messages = [ChatCompletionParameters.Message(role: .system, content: .text(systemPrompt))] + history
            let params = ChatCompletionParameters(messages: messages, model: .custom(config.model), tools: tools())

            var liveText = ""
            var toolAcc: [Int: (id: String, name: String, args: String)] = [:]
            var lastEmit = Date.distantPast
            // Throttle markdown re-renders so fast token streams don't flicker.
            func emit(force: Bool) {
                guard force || Date().timeIntervalSince(lastEmit) > 0.07 else { return }
                lastEmit = Date()
                if let id = assistantTurnID, let i = turns.firstIndex(where: { $0.id == id }) {
                    turns[i].text = liveText
                } else if !liveText.isEmpty {
                    let t = Turn(role: "assistant", text: liveText)
                    assistantTurnID = t.id
                    turns.append(t)
                }
            }
            do {
                let stream = try await service.startStreamedChat(parameters: params)
                for try await chunk in stream {
                    guard let choice = chunk.choices?.first else { continue }
                    if let c = choice.delta?.content, !c.isEmpty {
                        liveText += c
                        emit(force: false)
                    }
                    for tc in choice.delta?.toolCalls ?? [] {
                        // Some servers omit `index` while streaming; a chunk with a
                        // new id starts a new call, otherwise it continues the last.
                        let idx: Int
                        if let i = tc.index { idx = i }
                        else if tc.id != nil { idx = toolAcc.count }
                        else { idx = max(0, toolAcc.count - 1) }
                        var e = toolAcc[idx] ?? ("", "", "")
                        if let id = tc.id { e.id = id }
                        if let n = tc.function.name { e.name = n }
                        e.args += tc.function.arguments
                        toolAcc[idx] = e
                    }
                }
                emit(force: true)   // flush final tokens
            } catch {
                if !(error is CancellationError) && !Task.isCancelled {
                    turns.append(Turn(role: "error", text: "⚠️ \(error.localizedDescription)"))
                }
                return
            }
            if Task.isCancelled { return }

            guard !toolAcc.isEmpty else { return }   // final answer streamed; done

            // Record the assistant's tool-call message, run the tools, feed results back.
            let calls = toolAcc.sorted { $0.key < $1.key }.map { $0.value }
            let toolCalls: [ToolCall] = calls.map {
                ToolCall(id: $0.id, function: .init(arguments: $0.args, name: $0.name))
            }
            history.append(.init(role: .assistant, content: .text(liveText), toolCalls: toolCalls))
            for c in calls {
                let args = (try? JSONSerialization.jsonObject(with: Data(c.args.utf8))) as? [String: Any] ?? [:]
                let labels = toolLabels(c.name, args)
                if let l = labels { startStep(l.0) }
                let result = await runTool(c.name, args)
                if let l = labels { endStep(l.1) }
                history.append(.init(role: .tool, content: .text(result), toolCallID: c.id))
            }
            assistantTurnID = nil   // next streamed text is a fresh turn
        }
    }

    func reset() { history = []; turns = [] }
}
