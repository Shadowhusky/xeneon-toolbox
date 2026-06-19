import Foundation

/// Points the assistant at any OpenAI-compatible chat endpoint. The same shape
/// works for OpenAI, Ollama (`http://localhost:11434/v1`), and LM Studio
/// (`http://localhost:1234/v1`) — only the base URL, model, and optional key
/// change. Edit `~/.config/xeneon-toolbox/chat.json` to configure.
public struct ChatConfig: Codable, Sendable, Equatable {
    public var baseURL: String
    public var model: String
    public var apiKey: String?
    public var systemPrompt: String?

    public init(baseURL: String, model: String, apiKey: String? = nil, systemPrompt: String? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
    }

    public static let presets: [(name: String, config: ChatConfig)] = [
        ("Ollama (local)", ChatConfig(baseURL: "http://localhost:11434/v1", model: "llama3.2")),
        ("LM Studio (local)", ChatConfig(baseURL: "http://localhost:1234/v1", model: "local-model")),
        ("OpenAI", ChatConfig(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini")),
    ]

    public static var configURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/xeneon-toolbox", isDirectory: true)
        return dir.appendingPathComponent("chat.json")
    }

    /// The saved config, or nil if the assistant hasn't been set up yet.
    public static func loadSaved() -> ChatConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(ChatConfig.self, from: data)
    }

    public func save() {
        try? FileManager.default.createDirectory(at: Self.configURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pretty.encode(self) {
            try? data.write(to: Self.configURL)
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

public enum ChatError: LocalizedError {
    case badURL
    case http(Int, String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid base URL"
        case .http(let code, let body): return "Server error \(code): \(body)"
        case .empty: return "No response from the model"
        }
    }
}

public struct ChatClient {
    public let config: ChatConfig
    public init(config: ChatConfig) { self.config = config }

    /// Lists models for the dropdown. Queries the OpenAI-compatible `/models`
    /// (OpenAI, Ollama, LM Studio) AND, when present, LM Studio's native
    /// `/api/v0/models` — which lists EVERY installed model (even ones not
    /// currently loaded) and tags each with a `type`, so embedding models (which
    /// can't chat) are dropped. Results from both are merged.
    public static func listModels(baseURL: String, apiKey: String?) async -> [String] {
        func get(_ urlString: String) async -> [[String: Any]] {
            guard let url = URL(string: urlString) else { return [] }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            if let k = apiKey, !k.isEmpty { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]] else { return [] }
            return arr
        }

        var models = Set<String>()

        // LM Studio native API: all installed models, with a `type` to filter on.
        var host = baseURL
        if host.hasSuffix("/v1") { host = String(host.dropLast(3)) }
        else if host.hasSuffix("/v1/") { host = String(host.dropLast(4)) }
        if host.hasSuffix("/") { host = String(host.dropLast()) }
        for m in await get(host.appending("/api/v0/models")) {
            if (m["type"] as? String) == "embeddings" { continue }
            if let id = m["id"] as? String { models.insert(id) }
        }

        // OpenAI-compatible endpoint (and the fallback for non-LM-Studio servers).
        for m in await get(baseURL.appending("/models")) {
            // /v1/models has no type; skip obvious embedding models by name.
            if let id = m["id"] as? String, !id.lowercased().contains("embed") { models.insert(id) }
        }

        return models.sorted()
    }

    public func reply(to history: [(role: String, content: String)]) async throws -> String {
        guard let url = URL(string: config.baseURL.appending("/chat/completions")) else { throw ChatError.badURL }

        var messages: [[String: String]] = []
        if let sys = config.systemPrompt, !sys.isEmpty { messages.append(["role": "system", "content": sys]) }
        messages += history.map { ["role": $0.role, "content": $0.content] }

        let body: [String: Any] = ["model": config.model, "messages": messages, "stream": false]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = config.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ChatError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatError.empty
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
