import Foundation

/// Turns address-bar input into a web URL. Local development hosts deliberately
/// default to HTTP; public domains default to HTTPS; everything else is searched.
public enum WebAddress {
    public static func resolve(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let explicit = URL(string: value),
           let scheme = explicit.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return explicit
        }

        if !value.contains(where: \.isWhitespace), looksLikeHost(value) {
            let scheme = isLocalHost(value) ? "http" : "https"
            return URL(string: "\(scheme)://\(value)")
        }

        var search = URLComponents(string: "https://www.google.com/search")
        search?.queryItems = [URLQueryItem(name: "q", value: value)]
        return search?.url
    }

    private static func looksLikeHost(_ value: String) -> Bool {
        let host = hostPart(value)
        return host == "localhost"
            || host.hasSuffix(".local")
            || host.contains(".")
            || (host.hasPrefix("[") && host.hasSuffix("]"))
    }

    private static func isLocalHost(_ value: String) -> Bool {
        let host = hostPart(value).lowercased()
        if host == "localhost" || host.hasSuffix(".local") || host == "[::1]" { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10
            || parts[0] == 127
            || (parts[0] == 169 && parts[1] == 254)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }

    private static func hostPart(_ value: String) -> String {
        let authority = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
        if authority.hasPrefix("[") {
            return authority.prefix(through: authority.firstIndex(of: "]") ?? authority.index(before: authority.endIndex))
                .lowercased()
        }
        return authority.split(separator: ":", maxSplits: 1).first.map { $0.lowercased() } ?? authority.lowercased()
    }
}
