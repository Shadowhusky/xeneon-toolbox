import Foundation

/// The Mac's public address, for the Network detail. Fetched on demand and
/// cached for an hour — it rarely changes and the lookup is a network call.
actor PublicIP {
    static let shared = PublicIP()
    private var cached: (value: String, at: Date)?

    func fetch() async -> String? {
        if let c = cached, Date().timeIntervalSince(c.at) < 3600 { return c.value }
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("XeneonToolbox", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String, !ip.isEmpty else { return cached?.value }
        cached = (ip, Date())
        return ip
    }
}
