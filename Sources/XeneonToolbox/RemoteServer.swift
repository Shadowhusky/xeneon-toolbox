import Foundation
import Network
import Darwin

/// A tiny dependency-free HTTP server that serves a responsive web remote and a
/// small JSON control API, so the Edge can be driven from a phone or PC on the
/// same network: change page, rest/wake, adjust brightness, and talk to the
/// assistant. Binds to the first free port from a small range. A per-install
/// token (carried in the URL) gates the API.
@MainActor
final class RemoteServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var urls: [String] = []

    private weak var model: ToolboxModel?
    private var listener: NWListener?
    private var candidates: [UInt16] = []
    let token: String

    private static let portRange: [UInt16] = Array(8765...8784)

    init(model: ToolboxModel) {
        self.model = model
        if let t = UserDefaults.standard.string(forKey: "remote.token"), !t.isEmpty {
            token = t
        } else {
            let t = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
            UserDefaults.standard.set(String(t), forKey: "remote.token")
            token = String(t)
        }
    }

    func start() {
        guard listener == nil else { return }
        candidates = Self.portRange
        tryNextPort()
    }

    func stop() {
        listener?.cancel(); listener = nil
        running = false; port = 0; urls = []
    }

    private func tryNextPort() {
        guard let p = candidates.first else { return }   // none free in range — give up quietly
        candidates.removeFirst()
        guard let nwPort = NWEndpoint.Port(rawValue: p) else { tryNextPort(); return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: nwPort) else { tryNextPort(); return }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.onListenerState(state, port: p, listener: l) }
        }
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.accept(conn) }
        }
        l.start(queue: .main)
    }

    private func onListenerState(_ state: NWListener.State, port p: UInt16, listener l: NWListener) {
        switch state {
        case .ready:
            listener = l
            port = p
            running = true
            urls = Self.lanIPv4().map { "http://\($0):\(p)/?t=\(token)" }
            fputs("REMOTE ready: http://localhost:\(p)/?t=\(token)\n", stderr)
            urls.forEach { fputs("REMOTE lan: \($0)\n", stderr) }
        case .failed:
            l.cancel()
            if listener == nil { tryNextPort() }   // this port was taken — try the next
        default:
            break
        }
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        pump(conn, Data())
    }

    private func pump(_ conn: NWConnection, _ acc: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { conn.cancel(); return }
                var buf = acc
                if let data, !data.isEmpty { buf.append(data) }
                if let req = Self.parse(buf) {
                    let r = self.route(req)
                    self.respond(conn, status: r.status, type: r.type, body: r.body)
                } else if isComplete || error != nil {
                    conn.cancel()
                } else {
                    self.pump(conn, buf)
                }
            }
        }
    }

    private func respond(_ conn: NWConnection, status: String, type: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(type)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8); out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Routing

    private func route(_ req: Req) -> (status: String, type: String, body: Data) {
        if req.path == "/" || req.path.isEmpty {
            return ("200 OK", "text/html; charset=utf-8", Data(Self.html.utf8))
        }
        guard req.path.hasPrefix("/api/") else {
            return ("404 Not Found", "text/plain", Data("Not found".utf8))
        }
        guard req.query["t"] == token else {
            return ("401 Unauthorized", "application/json", Data(#"{"error":"unauthorized"}"#.utf8))
        }
        guard let model else { return json(["error": "unavailable"]) }

        switch (req.method, req.path) {
        case ("GET", "/api/state"):
            return json(state(model))
        case ("GET", "/api/agent"):
            return json(["turns": turns(model), "busy": model.agent.busy])
        case ("GET", "/api/image"):
            if let idStr = req.query["id"], let uuid = UUID(uuidString: idStr),
               let turn = model.agent.turns.first(where: { $0.id == uuid }),
               case .image(let data)? = turn.card {
                let png = data.starts(with: [0x89, 0x50]) || !data.starts(with: [0xFF, 0xD8])
                return ("200 OK", png ? "image/png" : "image/jpeg", data)
            }
            return ("404 Not Found", "text/plain", Data())
        case ("POST", "/api/route"):
            if let r = body(req)["route"] as? String, let route = AppRoute(rawValue: r == "assistant" ? "chat" : r) {
                model.route = route
                if model.displayMode != .full { model.setDisplay(.full) }
            }
            return json(["ok": true])
        case ("POST", "/api/display"):
            switch body(req)["mode"] as? String {
            case "minimal": model.setDisplay(.minimal)
            case "sleep", "rest": model.setDisplay(.sleep)
            case "full", "wake": model.setDisplay(.full)
            default: break
            }
            return json(["ok": true])
        case ("POST", "/api/brightness"):
            if let l = body(req)["level"] as? Int { model.applyBrightness(l) }
            return json(["ok": true])
        case ("POST", "/api/agent"):
            if let t = (body(req)["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                if model.route != .chat { model.route = .chat }
                if model.displayMode != .full { model.setDisplay(.full) }
                model.agent.send(text: t, imageDataURL: nil)
            }
            return json(["ok": true])
        default:
            return ("404 Not Found", "text/plain", Data("Not found".utf8))
        }
    }

    private func state(_ m: ToolboxModel) -> [String: Any] {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM · HH:mm"
        let touch: String
        switch m.touchStatus { case .active: touch = "active"; case .searching: touch = "searching"; case .off: touch = "off" }
        return [
            "route": m.route.rawValue,
            "display": display(m.displayMode),
            "cpu": Int((m.metrics.snap.cpu * 100).rounded()),
            "mem": Int((m.metrics.snap.memFraction * 100).rounded()),
            "brightness": m.brightness,
            "canBrightness": m.canControlBacklight,
            "touch": touch,
            "time": f.string(from: Date()),
        ]
    }

    private func display(_ d: DisplayMode) -> String {
        switch d { case .full: return "full"; case .minimal: return "minimal"; case .sleep: return "sleep" }
    }

    private func turns(_ m: ToolboxModel) -> [[String: Any]] {
        let mapped: [[String: Any]] = m.agent.turns.compactMap { t in
            switch t.role {
            case "user", "assistant", "error":
                let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return ["role": t.role, "text": text]
            case "card":
                guard let card = t.card else { return nil }
                return ["role": "card", "card": Self.serialize(card, id: t.id)]
            default:
                return nil   // skip ephemeral "tools" activity
            }
        }
        return Array(mapped.suffix(60))
    }

    private static func serialize(_ card: AgentCard, id: UUID) -> [String: Any] {
        switch card {
        case .processes(let rows):
            return ["type": "processes", "rows": rows.map { ["name": $0.name, "cpu": Int($0.cpu.rounded()), "mem": Int($0.mem.rounded())] }]
        case .generic(let title, let rows):
            return ["type": "generic", "title": title, "rows": rows.map { ["label": $0.label, "value": $0.value] }]
        case .chart(let title, let points, let line):
            return ["type": "chart", "title": title, "line": line, "points": points.map { ["label": $0.label, "value": $0.value] }]
        case .table(let title, let headers, let rows):
            return ["type": "table", "title": title, "headers": headers, "rows": rows]
        case .image:
            return ["type": "image", "id": id.uuidString]
        }
    }

    // MARK: - HTTP helpers

    private struct Req { let method: String; let path: String; let query: [String: String]; let headers: [String: String]; let body: Data }

    private func json(_ obj: Any) -> (status: String, type: String, body: Data) {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return ("200 OK", "application/json", data)
    }

    private func body(_ req: Req) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:]
    }

    /// Parse a complete HTTP request from the buffer, or nil if more bytes are needed.
    private static func parse(_ buf: Data) -> Req? {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = buf.range(of: sep) else { return nil }
        let head = String(decoding: buf[buf.startIndex..<r.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let request = lines.removeFirst().components(separatedBy: " ")
        guard request.count >= 2 else { return nil }
        let method = request[0]
        let target = request[1]
        var path = target, query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<q])
            for pair in target[target.index(after: q)...].components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 { query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
        }
        var headers: [String: String] = [:]
        for line in lines {
            if let c = line.firstIndex(of: ":") {
                headers[line[line.startIndex..<c].lowercased().trimmingCharacters(in: .whitespaces)] =
                    line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let bodyStart = r.upperBound
        let bodyLen = Int(headers["content-length"] ?? "0") ?? 0
        let available = buf.distance(from: bodyStart, to: buf.endIndex)
        if available < bodyLen { return nil }   // wait for the rest of the body
        let body = Data(buf[bodyStart..<buf.index(bodyStart, offsetBy: bodyLen)])
        return Req(method: method, path: path, query: query, headers: headers, body: body)
    }

    /// Non-loopback IPv4 addresses on Ethernet/Wi-Fi interfaces.
    static func lanIPv4() -> [String] {
        var out: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
               let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                if name.hasPrefix("en") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if !ip.hasPrefix("127.") && !ip.isEmpty { out.append(ip) }
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        freeifaddrs(head)
        return Array(Set(out)).sorted()
    }
}
