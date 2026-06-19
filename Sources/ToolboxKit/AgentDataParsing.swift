import Foundation

/// Pure parsing for the assistant's generative-UI tool arguments. Models emit
/// tabular/list data in inconsistent shapes — arrays, delimited strings, objects,
/// or even malformed JSON — so these helpers coerce whatever arrives into the
/// shapes the cards expect. Kept pure (and here) so they can be unit-tested.
public enum AgentDataParsing {

    public static func stringify(_ v: Any) -> String {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespaces) }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    /// A list of cell strings from an array, or a string with cells separated by '|' or ','.
    public static func cells(from raw: Any?) -> [String] {
        if let arr = raw as? [Any] { return arr.map { stringify($0) }.filter { !$0.isEmpty } }
        if let s = raw as? String {
            let sep: Character = s.contains("|") ? "|" : ","
            return s.split(separator: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }

    /// Rows of cells from a 2D array, an array of delimited strings, or a
    /// (possibly malformed) JSON string.
    public static func rows(from raw: Any?) -> [[String]] {
        if let arr = raw as? [Any] {
            return arr.compactMap { el -> [String]? in
                if let row = el as? [Any] { return row.map { stringify($0) } }
                let c = cells(from: el)
                return c.isEmpty ? nil : c
            }
        }
        if let s = raw as? String {
            // Try parsing a JSON 2D array, repairing a missing leading bracket.
            for candidate in [s, "[\(s)"] {
                if let data = candidate.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    return parsed.map { $0.map { stringify($0) } }
                }
            }
            return s.split(whereSeparator: \.isNewline).map { cells(from: String($0)) }.filter { !$0.isEmpty }
        }
        return []
    }

    /// A (label, value) pair from one card/chart item — a "Label: value" string
    /// or a {label/name, value} object.
    public static func labelValue(from item: Any) -> (label: String, value: String) {
        if let s = item as? String {
            if let r = s.range(of: ":") {
                return (String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces),
                        String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
            return (s.trimmingCharacters(in: .whitespaces), "")
        }
        if let d = item as? [String: Any] {
            let label = d["label"] ?? d["name"] ?? d["key"] ?? d["title"]
            let value = d["value"] ?? d["val"] ?? d["count"] ?? d["amount"] ?? d["y"]
            return (label.map(stringify) ?? "", value.map(stringify) ?? "")
        }
        return (stringify(item), "")
    }
}
