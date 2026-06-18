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

/// A visual artifact the agent can render into the transcript (generative UI).
enum AgentCard {
    case processes([ProcRow])
}

/// One step in the agent's tool activity — shown live (working) then completed.
struct ToolStep: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool
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

    private var config: ChatConfig
    private weak var app: ToolboxModel?
    private var history: [SwiftOpenAI.ChatCompletionParameters.Message] = []

    init(config: ChatConfig, app: ToolboxModel?) {
        self.config = config
        self.app = app
    }

    func update(config: ChatConfig) { self.config = config }

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
            return "tab=\(app.route.rawValue); touch=\(app.touchOn ? "on" : "off"); cpu=\(Int(s.cpu*100))%; mem=\(Fmt.gb(s.memUsed))/\(Fmt.gb(s.memTotal))GB; diskFree=\(Fmt.gb(s.diskFree))GB; uptime=\(Fmt.uptime(s.uptime))"
        case "show_top_processes":
            let n = (args["count"] as? Int) ?? 6
            let rows = topProcesses(n)
            turns.append(Turn(role: "card", text: "", card: .processes(rows)))
            return "Displayed a card with the top \(rows.count) processes: " + rows.map { "\($0.name) \(Int($0.cpu))%" }.joined(separator: ", ")
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
        default:
            return "Unknown tool \(name)."
        }
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
        You are the built-in assistant inside Xeneon Toolbox, a macOS app on a Corsair Xeneon Edge — a 2560x720 ultrawide touchscreen. Tabs: Dashboard (live system telemetry), Clock (world clocks + focus timer), Games (embeds the 山海残卷 card roguelike and Rhythm Plus), and Assistant (you). "Touch" is the embedded driver that lets the user tap the Edge. Use your tools to inspect state and control the app when asked. Keep answers concise — the screen is small and wide.
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

        Task { await runLoop() }
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
        default: return (name, name)
        }
    }

    private func runLoop() async {
        defer { busy = false }
        var assistantTurnID: UUID?
        toolsTurnID = nil

        for _ in 0..<5 {
            let messages = [ChatCompletionParameters.Message(role: .system, content: .text(systemPrompt))] + history
            let params = ChatCompletionParameters(messages: messages, model: .custom(config.model), tools: tools())

            var liveText = ""
            var toolAcc: [Int: (id: String, name: String, args: String)] = [:]
            do {
                let stream = try await service.startStreamedChat(parameters: params)
                for try await chunk in stream {
                    guard let choice = chunk.choices?.first else { continue }
                    if let c = choice.delta?.content, !c.isEmpty {
                        liveText += c
                        if let id = assistantTurnID, let i = turns.firstIndex(where: { $0.id == id }) {
                            turns[i].text = liveText
                        } else {
                            let t = Turn(role: "assistant", text: liveText)
                            assistantTurnID = t.id
                            turns.append(t)
                        }
                    }
                    for tc in choice.delta?.toolCalls ?? [] {
                        let idx = tc.index ?? 0
                        var e = toolAcc[idx] ?? ("", "", "")
                        if let id = tc.id { e.id = id }
                        if let n = tc.function.name { e.name = n }
                        e.args += tc.function.arguments
                        toolAcc[idx] = e
                    }
                }
            } catch {
                turns.append(Turn(role: "error", text: "⚠️ \(error.localizedDescription)"))
                return
            }

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
