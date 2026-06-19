import Foundation
import AppKit
import SwiftOpenAI
import ToolboxKit

/// An agentic assistant: streams replies, accepts images, and can drive the
/// toolbox via tools (it knows the app's tabs, stats, and controls).
struct ProcRow: Identifiable, Codable {
    var id = UUID()
    let name: String
    let cpu: Double   // percent
    let mem: Double   // percent
}

struct CardRow: Identifiable, Codable {
    var id = UUID()
    let label: String
    let value: String
}

struct ChartPoint: Identifiable, Codable {
    var id = UUID()
    let label: String
    let value: Double
}

/// A visual artifact the agent can render into the transcript (generative UI).
enum AgentCard: Codable {
    case processes([ProcRow])
    case generic(title: String, rows: [CardRow])
    case chart(title: String, points: [ChartPoint], line: Bool)
    case table(title: String, headers: [String], rows: [[String]])
    case image(Data)

    /// Images are large; they're kept in-session only, not persisted to disk.
    var isImage: Bool { if case .image = self { return true }; return false }
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
    let role: String   // "user" | "assistant" | "card"
    let text: String
    var card: AgentCard? = nil
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
    private var toolsUnsupported = false   // set if the endpoint rejects tool params

    private struct StoredFile: Codable { var conversations: [StoredConversation]; var activeID: UUID }
    private static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox/conversations.json")
    }

    /// Durable facts the user asks the assistant to remember (persists across
    /// conversations and restarts; injected into the system prompt).
    private var memories: [String] = []
    private static var memoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox/memory.json")
    }

    init(config: ChatConfig, app: ToolboxModel?) {
        self.config = config
        self.app = app
        loadStore()
        if let d = try? Data(contentsOf: Self.memoryURL),
           let m = try? JSONDecoder().decode([String].self, from: d) { memories = m }
    }

    private func saveMemories() {
        try? FileManager.default.createDirectory(at: Self.memoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(memories) { try? d.write(to: Self.memoryURL) }
    }

    func update(config: ChatConfig) { self.config = config; toolsUnsupported = false }

    // MARK: - Conversations

    func newConversation() {
        saveActive()
        let c = StoredConversation(id: UUID(), title: "New chat", messages: [], updated: Date())
        conversations.insert(c, at: 0)
        activeID = c.id
        turns = []; history = []; alwaysAllowed.removeAll()
        writeStore()
    }

    func select(_ id: UUID) {
        guard id != activeID else { return }
        saveActive()
        activeID = id
        alwaysAllowed.removeAll()   // approvals are per-conversation, not process-wide
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
        turns = c.messages.map { m in
            m.role == "card" ? Turn(role: "card", text: "", card: m.card) : Turn(role: m.role, text: m.text)
        }
        history = c.messages.compactMap { m in
            (m.role == "user" || m.role == "assistant")
                ? .init(role: m.role == "user" ? .user : .assistant, content: .text(m.text)) : nil
        }
    }

    private func saveActive() {
        guard let i = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        conversations[i].messages = turns.compactMap { t -> StoredMessage? in
            if (t.role == "user" || t.role == "assistant") && !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return StoredMessage(role: t.role, text: t.text)
            }
            if t.role == "card", let card = t.card, !card.isImage {
                return StoredMessage(role: "card", text: "", card: card)
            }
            return nil
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
        let context = conversations[i].messages
            .filter { $0.role == "user" || $0.role == "assistant" }
            .prefix(4).map { "\($0.role): \($0.text)" }.joined(separator: "\n")
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
        // Auto-downgrade https→http for local/LAN servers (they're plain HTTP).
        var host = ChatClient.resolveBaseURL(config.baseURL)
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
            tool("set_display_mode", "Change the screen mode: full (normal UI), minimal (clock + basics on black), or sleep (black screen, pauses monitoring). Tapping the screen wakes it.",
                 ["mode": .init(type: .string, enum: ["full", "minimal", "sleep"])], required: ["mode"]),
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
            tool("show_table", "Display tabular data as a touch-friendly table (good for comparisons with multiple columns). 'headers' is the column names. 'rows' is a list of rows, where each row is a list of cell strings (one per column).",
                 ["title": .init(type: .string),
                  "headers": .init(type: .array, items: .init(type: .string)),
                  "rows": .init(type: .array, items: .init(type: .array, items: .init(type: .string)))],
                 required: ["headers", "rows"]),
            tool("generate_image", "Generate an image from a text prompt and show it on screen. Needs an image-capable endpoint with an API key configured in Assistant settings.",
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
            tool("find_files", "Find files anywhere on this Mac by name or keyword via Spotlight, when you don't know the exact path. Returns up to 20 matching paths.",
                 ["query": .init(type: .string)], required: ["query"]),
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
            tool("get_weather", "Get current weather (temperature + conditions) for any city or place by name.",
                 ["location": .init(type: .string)], required: ["location"]),
            // Long-term memory
            tool("remember", "Save a durable fact about the user or their preferences to long-term memory — e.g. their name, their rig/setup, units they prefer, recurring tasks. Use whenever the user shares something worth remembering for later conversations.",
                 ["fact": .init(type: .string)], required: ["fact"]),
            tool("forget", "Remove remembered facts that contain the given text.",
                 ["fact": .init(type: .string)], required: ["fact"]),
            // To-dos & reminders (shown in the Tasks tab)
            tool("add_todo", "Add a to-do or reminder to the user's Tasks list. Set 'due' (ISO 8601 local datetime, e.g. 2026-06-19T18:30) to make it a reminder that notifies — compute it from the current local time above. Set 'repeat' to daily or weekly for a recurring reminder.",
                 ["title": .init(type: .string), "due": .init(type: .string),
                  "repeat": .init(type: .string, enum: ["daily", "weekly"])], required: ["title"]),
            tool("list_todos", "List the user's current to-dos and reminders (numbered, with done status and due times)."),
            tool("complete_todo", "Toggle a to-do done/undone. Identify it by its number from list_todos or a word from its title.",
                 ["task": .init(type: .string)], required: ["task"]),
            tool("delete_todo", "Delete a to-do. Identify it by its number from list_todos or a word from its title.",
                 ["task": .init(type: .string)], required: ["task"]),
        ]
    }

    private func runTool(_ name: String, _ args: [String: Any]) async -> String {
        switch name {
        case "navigate":
            // The tab is called "Assistant" in the UI but its route value is "chat".
            guard let app, let t = args["tab"] as? String else { return "Unknown tab." }
            guard let r = (t == "assistant") ? .chat : AppRoute(rawValue: t) else { return "Unknown tab." }
            app.route = r; return "Opened \(r.title)."
        case "set_touch":
            guard let app else { return "App unavailable." }
            let on = args["enabled"] as? Bool ?? false
            on ? app.startTouch() : app.stopTouch()
            return "Touch \(on ? "enabled" : "disabled")."
        case "set_display_mode":
            guard let app, let m = args["mode"] as? String else { return "App unavailable." }
            switch m {
            case "minimal": app.setDisplay(.minimal)
            case "sleep": app.setDisplay(.sleep)
            default: app.setDisplay(.full)
            }
            return "Display set to \(m)."
        case "open_game":
            guard let app else { return "App unavailable." }
            let g = (args["game"] as? String) == "rhythm" ? "rhythm" : "shanhai"
            app.gamePref = g; app.route = .games
            return "Opened \(g == "rhythm" ? "Rhythm Plus" : "山海残卷")."
        case "get_app_state":
            guard let app else { return "App unavailable." }
            let s = app.metrics.snap
            let tabName = app.route == .chat ? "assistant" : app.route.rawValue
            var out = "tab=\(tabName); touch=\(app.touchStatus == .active ? "active" : app.touchOn ? "searching" : "off"); cpu=\(Int(s.cpu*100))%; mem=\(Fmt.gb(s.memUsed))/\(Fmt.gb(s.memTotal))GB; diskFree=\(Fmt.gb(s.diskFree))GB; uptime=\(Fmt.uptime(s.uptime))"
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
            let rows: [CardRow] = (args["items"] as? [Any] ?? []).compactMap { item in
                let lv = AgentDataParsing.labelValue(from: item)
                return lv.label.isEmpty && lv.value.isEmpty ? nil : CardRow(label: lv.label, value: lv.value)
            }
            guard !rows.isEmpty else { return "No items to show." }
            turns.append(Turn(role: "card", text: "", card: .generic(title: title, rows: rows)))
            return "Displayed a card titled \(title) with \(rows.count) items."
        case "show_chart":
            let title = (args["title"] as? String) ?? "Chart"
            let isLine = (args["type"] as? String) == "line"
            let points: [ChartPoint] = (args["items"] as? [Any] ?? []).compactMap { item in
                let lv = AgentDataParsing.labelValue(from: item)
                let num = lv.value.filter { "0123456789.-".contains($0) }
                guard let d = Double(num) else { return nil }
                return ChartPoint(label: lv.label, value: d)
            }
            guard !points.isEmpty else { return "No numeric data to chart." }
            turns.append(Turn(role: "card", text: "", card: .chart(title: title, points: points, line: isLine)))
            return "Displayed a \(isLine ? "line" : "bar") chart titled \(title) with \(points.count) points."
        case "show_table":
            let title = (args["title"] as? String) ?? "Table"
            let headers = AgentDataParsing.cells(from: args["headers"])
            let rows = AgentDataParsing.rows(from: args["rows"])
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
        case "find_files":
            return findFiles((args["query"] as? String) ?? "")
        case "add_todo":
            guard let app else { return "App unavailable." }
            let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return "No task title given." }
            let due = (args["due"] as? String).flatMap { parseDate($0) }
            let asked = Recurrence(rawValue: (args["repeat"] as? String) ?? "none") ?? .none
            let rec = due == nil ? .none : asked   // recurrence needs a time to anchor + notify on
            app.todos.add(title, dueAt: due, recurrence: rec)
            if asked != .none, due == nil {
                return "Added “\(title)”. A recurring reminder needs a time — tell me when (e.g. every day at 9 AM) and I'll set it to repeat."
            }
            let suffix = rec != .none ? " (\(rec.rawValue))" : ""
            return due != nil ? "Added reminder “\(title)” for \(formatDue(due!))\(suffix)." : "Added to-do “\(title)”."
        case "list_todos":
            guard let app else { return "App unavailable." }
            let items = app.todos.sorted
            guard !items.isEmpty else { return "The task list is empty." }
            var out = "Tasks:\n"
            for (i, t) in items.enumerated() {
                var line = "\(i + 1). [\(t.done ? "x" : " ")] \(t.title)"
                if let d = t.dueAt { line += " (due \(formatDue(d))\(t.isOverdue ? " — OVERDUE" : ""))" }
                if t.recurrence != .none { line += " [repeats \(t.recurrence.rawValue)]" }
                out += line + "\n"
            }
            return out
        case "complete_todo":
            guard let app else { return "App unavailable." }
            guard let item = TodoMatch.resolve((args["task"] as? String) ?? "", in: app.todos.sorted) else { return "No matching task found." }
            switch app.todos.toggle(item.id) {
            case .completed: return "Marked done: “\(item.title)”."
            case .reopened: return "Reopened: “\(item.title)”."
            case .rolledForward(let next): return "Completed “\(item.title)” — next occurrence \(formatDue(next))."
            case .notFound: return "No matching task found."
            }
        case "delete_todo":
            guard let app else { return "App unavailable." }
            guard let item = TodoMatch.resolve((args["task"] as? String) ?? "", in: app.todos.sorted) else { return "No matching task found." }
            app.todos.remove(item.id)
            return "Deleted “\(item.title)”."
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
        case "get_weather":
            return await fetchWeather((args["location"] as? String) ?? "")
        case "remember":
            let f = (args["fact"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !f.isEmpty else { return "Nothing to remember." }
            if !memories.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) {
                memories.append(f); saveMemories()
            }
            return "Saved to memory: \(f)"
        case "forget":
            let q = (args["fact"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return "Nothing specified to forget." }
            let before = memories.count
            memories.removeAll { $0.lowercased().contains(q) }
            saveMemories()
            return before == memories.count ? "No matching memory found." : "Forgotten (\(before - memories.count) item(s))."
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

    private static let webUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

    private func webSearch(_ query: String) async -> String {
        guard !query.isEmpty,
              let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return "Invalid query." }
        if let r = await ddg("https://html.duckduckgo.com/html/?q=\(q)", query,
                             titlePat: "class=\"result__a\"[^>]*>(.*?)</a>",
                             snipPat: "class=\"result__snippet\"[^>]*>(.*?)</a>",
                             urlPat: "class=\"result__url\"[^>]*>(.*?)</a>") { return r }
        // Fallback: the lite endpoint has simpler, more stable markup.
        if let r = await ddg("https://lite.duckduckgo.com/lite/?q=\(q)", query,
                             titlePat: "class=\"result-link\"[^>]*>(.*?)</a>",
                             snipPat: "class=\"result-snippet\"[^>]*>(.*?)</td>",
                             urlPat: nil) { return r }
        return "No web results for \"\(query)\". Try rephrasing the query, or use fetch_url if you already know the page."
    }

    private func ddg(_ urlString: String, _ query: String, titlePat: String, snipPat: String, urlPat: String?) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(Self.webUA, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let titles = matches(in: html, pattern: titlePat).map { strip($0) }.filter { !$0.isEmpty }
        guard !titles.isEmpty else { return nil }
        let snippets = matches(in: html, pattern: snipPat).map { strip($0) }
        let urls = urlPat.map { matches(in: html, pattern: $0).map { strip($0) } } ?? []
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

    private func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.dateFormat = fmt; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private func formatDue(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }

    private func findFiles(_ query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return "No query." }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-name", q]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "File search unavailable." }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = out.split(separator: "\n").prefix(20)
        return lines.isEmpty ? "No files found matching \(q)." : lines.joined(separator: "\n")
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

    private func fetchWeather(_ location: String) async -> String {
        guard !location.isEmpty,
              let q = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let gurl = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1") else { return "Invalid location." }
        guard let (gd, _) = try? await URLSession.shared.data(from: gurl),
              let gj = try? JSONSerialization.jsonObject(with: gd) as? [String: Any],
              let res = (gj["results"] as? [[String: Any]])?.first,
              let lat = res["latitude"] as? Double, let lon = res["longitude"] as? Double else { return "Couldn't find a place called \(location)." }
        let name = (res["name"] as? String) ?? location
        let admin = (res["country"] as? String) ?? ""
        guard let wurl = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m"),
              let (wd, _) = try? await URLSession.shared.data(from: wurl),
              let wj = try? JSONSerialization.jsonObject(with: wd) as? [String: Any],
              let cur = wj["current"] as? [String: Any],
              let tempC = cur["temperature_2m"] as? Double else { return "Couldn't get weather for \(name)." }
        let code = (cur["weather_code"] as? Int) ?? -1
        let tempF = tempC * 9 / 5 + 32
        var out = "\(name)\(admin.isEmpty ? "" : ", \(admin)"): \(Int(tempC.rounded()))°C / \(Int(tempF.rounded()))°F, \(weatherText(code))"
        if let h = cur["relative_humidity_2m"] as? Double { out += ", humidity \(Int(h))%" }
        if let w = cur["wind_speed_10m"] as? Double { out += ", wind \(Int(w)) km/h" }
        return out + "."
    }

    private func weatherText(_ c: Int) -> String {
        switch c {
        case 0: return "clear sky"
        case 1, 2, 3: return "partly cloudy"
        case 45, 48: return "foggy"
        case 51...57: return "drizzle"
        case 61...67: return "rain"
        case 71...77: return "snow"
        case 80...82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95...99: return "thunderstorms"
        default: return "cloudy"
        }
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
        var p = """
        You are the built-in assistant inside Xeneon Toolbox, a macOS app on a Corsair Xeneon Edge — a 2560x720 ultrawide touchscreen. Tabs: Dashboard (live system telemetry), Clock (world clocks + focus timer), Games (embeds the 山海残卷 card roguelike and Rhythm Plus), and Assistant (you). "Touch" is the embedded driver that lets the user tap the Edge.

        Guidelines:
        - Answer questions directly here in the Assistant. Use web_search/fetch_url for current facts and get_weather for weather anywhere. Pick the clearest output: show_card for key/value stats or lists, show_table for multi-column comparisons, show_chart for numeric trends, generate_image for pictures. Don't force everything into one format.
        - When you render a card, table, or chart, DON'T also repeat the same data as a text table or list — the card already shows it. Add only a short sentence of insight, if anything.
        - Only use navigate or open_game when the user explicitly asks to switch tabs or open something — never navigate away just to answer a question.
        - Use get_app_state for live system info. Keep answers concise; the screen is small and wide.
        - When the user shares something durable about themselves or their setup (name, preferences, units, recurring needs), quietly call remember so you can use it later. Don't announce it unless asked.
        - The user has a Tasks list (to-dos + reminders). Use add_todo / list_todos / complete_todo / delete_todo to manage it. For "remind me to X at/in …", compute the due datetime from the current local time above and pass it as 'due' so it notifies.
        """
        p += "\n\nCurrent local time: " + DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short) + "."
        if !memories.isEmpty {
            p += "\n\nThings you remember about this user:\n" + memories.map { "- \($0)" }.joined(separator: "\n")
        }
        return p
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

    /// Re-run the last turn after an error — the user message is already in
    /// `history`, so just drop the error bubble and resume the loop (no dupe).
    func retryLast() {
        guard !busy, !history.isEmpty else { return }
        if turns.last?.role == "error" { turns.removeLast() }
        busy = true
        task = Task { await runLoop() }
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
        case "set_display_mode": let m = args["mode"] as? String ?? ""; return ("Setting display…", "Display → \(m)")
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
        case "find_files": let q = args["query"] as? String ?? ""; return ("Finding “\(q)”…", "Searched files for “\(q)”")
        case "add_todo": let t = args["title"] as? String ?? ""; return ("Adding task…", "Added “\(t)”")
        case "list_todos": return ("Checking tasks…", "Checked tasks")
        case "complete_todo": return ("Updating task…", "Updated task")
        case "delete_todo": return ("Deleting task…", "Deleted task")
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
        case "get_weather": let l = args["location"] as? String ?? ""; return ("Checking weather in \(l)…", "Checked weather in \(l)")
        case "remember": return ("Saving to memory…", "Remembered")
        case "forget": return ("Updating memory…", "Updated memory")
        default: return (name, name)
        }
    }

    private func runLoop() async {
        defer { busy = false; task = nil; writeStore(); maybeAutoTitle() }
        var assistantTurnID: UUID?
        toolsTurnID = nil

        let maxRounds = 10
        for round in 0..<maxRounds {
            let messages = [ChatCompletionParameters.Message(role: .system, content: .text(systemPrompt))] + history
            // On the final round, drop tools so the model must produce a text answer
            // (rather than calling another tool and hitting a dead-end).
            let lastRound = (round == maxRounds - 1)
            let params = ChatCompletionParameters(messages: messages, model: .custom(config.model),
                                                  tools: (toolsUnsupported || lastRound) ? nil : tools())

            var liveText = ""
            var toolAcc: [Int: (id: String, name: String, args: String)] = [:]
            var idForKey: [String: Int] = [:]
            var lastKey = -1
            var lastEmit = Date.distantPast
            // Throttle markdown re-renders so fast token streams don't flicker.
            func emit(force: Bool) {
                guard force || Date().timeIntervalSince(lastEmit) > 0.07 else { return }
                lastEmit = Date()
                if let id = assistantTurnID, let i = turns.firstIndex(where: { $0.id == id }) {
                    turns[i].text = liveText
                } else if !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        // Route deltas to the right call. Servers vary: some send
                        // `index`, some only an `id` on the first chunk, some neither
                        // on continuations — key by id and fall back to the last call.
                        let idx: Int
                        if let i = tc.index { idx = i }
                        else if let sid = tc.id, let e = idForKey[sid] { idx = e }
                        else if tc.id != nil { idx = toolAcc.count }
                        else { idx = lastKey >= 0 ? lastKey : 0 }
                        lastKey = idx
                        if let sid = tc.id { idForKey[sid] = idx }
                        var e = toolAcc[idx] ?? ("", "", "")
                        if let id = tc.id { e.id = id }
                        if let n = tc.function.name { e.name = n }
                        e.args += tc.function.arguments
                        toolAcc[idx] = e
                    }
                }
                emit(force: true)   // flush final tokens
            } catch {
                // Many local endpoints reject tool params; retry once without tools.
                let msg = error.localizedDescription.lowercased()
                if !toolsUnsupported, msg.contains("tool") || msg.contains("function") {
                    toolsUnsupported = true
                    continue
                }
                if !(error is CancellationError) && !Task.isCancelled {
                    var text = "⚠️ \(error.localizedDescription)"
                    let m = msg
                    if m.contains("tls") || m.contains("ssl") || m.contains("secure connection") {
                        text += "\n\nTip: local model servers use plain HTTP — set your endpoint to http:// (not https://)."
                    } else if m.contains("connection") || m.contains("could not connect") || m.contains("offline") {
                        text += "\n\nTip: check the endpoint host/port, and that the model server allows connections from this machine."
                    }
                    turns.append(Turn(role: "error", text: text))
                }
                return
            }
            if Task.isCancelled { return }

            guard !toolAcc.isEmpty else {
                // No tools — this was the final answer. Record it so multi-turn
                // follow-ups ("explain that more") have the assistant's own reply.
                if !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    history.append(.init(role: .assistant, content: .text(liveText)))
                }
                return
            }

            // Record the assistant's tool-call message, run the tools, feed results
            // back. Backfill missing ids so every tool_call has a unique, non-empty id
            // (some local servers omit them, which breaks the next request).
            let calls = toolAcc.sorted { $0.key < $1.key }.map { (key: $0.key, v: $0.value) }
            func cid(_ key: Int, _ id: String) -> String { id.isEmpty ? "call_\(key)" : id }
            let toolCalls: [ToolCall] = calls.map {
                ToolCall(id: cid($0.key, $0.v.id), function: .init(arguments: $0.v.args, name: $0.v.name))
            }
            history.append(.init(role: .assistant, content: .text(liveText), toolCalls: toolCalls))
            for c in calls {
                let id = cid(c.key, c.v.id)
                // If the user hit Stop mid-round, still answer every tool_call so the
                // assistant tool_calls message stays balanced (servers require it).
                if Task.isCancelled {
                    history.append(.init(role: .tool, content: .text("Cancelled."), toolCallID: id))
                    continue
                }
                let args = (try? JSONSerialization.jsonObject(with: Data(c.v.args.utf8))) as? [String: Any] ?? [:]
                let labels = toolLabels(c.v.name, args)
                if let l = labels { startStep(l.0) }
                let result = await runTool(c.v.name, args)
                if let l = labels { endStep(l.1) }
                history.append(.init(role: .tool, content: .text(result), toolCallID: id))
            }
            if Task.isCancelled { return }
            assistantTurnID = nil   // next streamed text is a fresh turn
        }
    }

    func reset() { history = []; turns = [] }
}
