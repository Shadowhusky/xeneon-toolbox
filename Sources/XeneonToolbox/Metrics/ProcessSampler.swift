import Foundation

/// Samples the top processes via `ps`, sorted by CPU or by resident memory.
/// Spawns a subprocess, so call it off the main thread.
enum ProcessSampler {
    /// Returns the top processes by CPU, or by resident memory (RSS) when
    /// `byMemory` is set. Sorts in Swift — macOS `ps` sort flags don't reliably
    /// match the printed columns — and includes RSS so callers can show real
    /// memory size (per-process `%MEM` is near-zero on large-RAM Macs).
    static func sample(byMemory: Bool = false, count: Int = 12) -> [ProcRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pid,pcpu,pmem,rss,comm"]
        let pipe = Pipe(); p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var rows: [ProcRow] = []
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // pid pcpu pmem rss comm…
            guard parts.count >= 5, let cpu = Double(parts[1]), let mem = Double(parts[2]), let rssKB = Double(parts[3]) else { continue }
            let name = parts[4...].joined(separator: " ")
            rows.append(ProcRow(name: name, cpu: cpu, mem: mem, rssMB: rssKB / 1024))
        }
        rows.sort { byMemory ? $0.rssMB > $1.rssMB : $0.cpu > $1.cpu }
        return Array(rows.prefix(max(1, count)))
    }
}
