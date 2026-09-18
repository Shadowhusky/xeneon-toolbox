import SwiftUI
import AppKit

enum MetricKind { case cpu, gpu, memory, network }

/// Connection facts for the Network panel.
struct NetworkInfo: Equatable {
    var ssid: String?
    var localIP: String?
    var publicIP: String?
    var loading = true
}

/// The full-strip console behind a gauge tile: the number and its history on
/// the left, what it's made of in the middle, who's responsible (with a way to
/// act on it) on the right.
struct MetricConsole: View {
    let kind: MetricKind
    let frame: MetricsFrame
    let detail: SystemDetail
    let processes: [ProcRow]
    let network: NetworkInfo
    var onBoost: () -> Void = {}
    var onClose: () -> Void = {}

    private var snap: MetricsSnapshot { frame.snap }

    var body: some View {
        DetailShell(title: title, icon: icon, tint: tint, subtitle: subtitle, actions: actions, onClose: onClose) {
            HStack(alignment: .top, spacing: 16) {
                left.frame(maxWidth: .infinity, maxHeight: .infinity)
                middle.frame(width: 560).frame(maxHeight: .infinity, alignment: .top)
                right.frame(width: 640).frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: Identity

    private var title: String {
        switch kind { case .cpu: return "Processor"; case .gpu: return "Graphics"; case .memory: return "Memory"; case .network: return "Network" }
    }
    private var icon: String {
        switch kind { case .cpu: return "cpu.fill"; case .gpu: return "cube.transparent.fill"; case .memory: return "memorychip.fill"; case .network: return "dot.radiowaves.up.forward" }
    }
    private var tint: Color {
        switch kind { case .cpu: return Theme.cpu; case .gpu: return Theme.gpu; case .memory: return Theme.memory; case .network: return Theme.netDown }
    }
    private var subtitle: String {
        switch kind {
        case .cpu:
            let split = detail.efficiencyCores > 0 ? "\(detail.performanceCores) performance and \(detail.efficiencyCores) efficiency cores" : "\(detail.cores.count) cores"
            return detail.chip.isEmpty ? split : "\(detail.chip), \(split)"
        case .gpu:
            return [detail.gpuName, detail.gpuCores > 0 ? "\(detail.gpuCores) cores" : ""].filter { !$0.isEmpty }.joined(separator: ", ")
        case .memory:
            return "\(Fmt.gb(snap.memTotal)) GB unified memory"
        case .network:
            if let ssid = network.ssid { return "Wi-Fi, \(ssid)" }
            if detail.interface.isEmpty { return "" }
            let label = detail.interfaces.first { $0.name == detail.interface }?.label
            return "Connected over \(label ?? detail.interface)"
        }
    }
    private var actions: [DetailAction] {
        let monitor = DetailAction(title: "Activity Monitor", icon: "waveform.path.ecg", tint: Theme.textSecondary) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"), configuration: .init())
        }
        let boost = DetailAction(title: "Boost", icon: "bolt.circle.fill", tint: Theme.accent, run: onBoost)
        switch kind {
        case .cpu, .memory: return [boost, monitor]
        case .gpu: return [monitor]
        case .network:
            return [DetailAction(title: "Network settings", icon: "gearshape.fill", tint: Theme.textSecondary) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { NSWorkspace.shared.open(url) }
            }]
        }
    }

    // MARK: Left: the number and its history

    private var history: [Double] {
        switch kind { case .cpu: return frame.cpu; case .gpu: return frame.gpu; case .memory: return frame.mem; case .network: return frame.netRx }
    }

    @ViewBuilder private var left: some View {
        VStack(alignment: .leading, spacing: 14) {
            if kind == .network { networkHeadline } else { percentHeadline }
            if kind == .network {
                GridGraph(series: [(frame.netRx, Theme.netDown), (frame.netTx, Theme.netUp)], topLabel: "last \(history.count * 2) s")
            } else {
                GridGraph(series: [(history, tint)], ceiling: 1, topLabel: "100%")
            }
        }
    }

    private var percentHeadline: some View {
        let now = history.last ?? 0, avg = history.isEmpty ? 0 : history.reduce(0, +) / Double(history.count), peak = history.max() ?? 0
        return HStack(alignment: .bottom, spacing: 28) {
            HeroStat(value: "\(Int((now * 100).rounded()))", unit: "%", caption: kind == .memory ? "in use now" : "load now", tint: tint)
            MiniStat(value: Fmt.percent(avg), caption: "average")
            MiniStat(value: Fmt.percent(peak), caption: "peak", tint: Theme.pressure(peak, base: Theme.textPrimary))
            if kind == .memory { MiniStat(value: "\(Fmt.gb(snap.memUsed)) GB", caption: "of \(Fmt.gb(snap.memTotal)) GB") }
            if kind == .cpu, let t = snap.thermals?.socC { MiniStat(value: "\(Int(t.rounded()))°", caption: "chip temperature", tint: Theme.heat) }
            if kind == .gpu, let t = snap.thermals?.gpuC { MiniStat(value: "\(Int(t.rounded()))°", caption: "GPU temperature", tint: Theme.heat) }
        }
    }

    private var networkHeadline: some View {
        let down = Fmt.rate(snap.netRx), up = Fmt.rate(snap.netTx)
        let peakDown = Fmt.rate(frame.netRx.max() ?? 0), peakUp = Fmt.rate(frame.netTx.max() ?? 0)
        return HStack(alignment: .bottom, spacing: 28) {
            HeroStat(value: down.value, unit: down.unit, caption: "download", tint: Theme.netDown, size: 72)
            HeroStat(value: up.value, unit: up.unit, caption: "upload", tint: Theme.netUp, size: 72)
            MiniStat(value: peakDown.value + " " + peakDown.unit, caption: "peak down", tint: Theme.netDown)
            MiniStat(value: peakUp.value + " " + peakUp.unit, caption: "peak up", tint: Theme.netUp)
        }
    }

    // MARK: Middle: what it's made of

    @ViewBuilder private var middle: some View {
        VStack(spacing: 14) {
            switch kind {
            case .cpu: coresPanel; loadPanel
            case .gpu: enginePanel; gpuMemoryPanel; gpuFacts; Spacer(minLength: 0)
            case .memory: compositionPanel; swapPanel
            case .network: connectionPanel; totalsPanel; Spacer(minLength: 0)
            }
        }
    }

    private var coresPanel: some View {
        let eff = detail.cores.filter(\.efficiency), perf = detail.cores.filter { !$0.efficiency }
        return ConsolePanel(title: "Cores", trailing: detail.cores.isEmpty ? nil : "\(detail.cores.count) total") {
            if detail.cores.isEmpty {
                Text("Reading cores…").font(.deck(14)).foregroundStyle(Theme.textFaint).frame(maxWidth: .infinity, minHeight: 150)
            } else {
                GeometryReader { g in
                    let gap: CGFloat = eff.isEmpty ? 0 : 20
                    let unit = (g.size.width - gap) / CGFloat(detail.cores.count)
                    HStack(alignment: .bottom, spacing: gap) {
                        if !eff.isEmpty { CoreGroup(label: "Efficiency", cores: eff, tint: Theme.netDown).frame(width: unit * CGFloat(eff.count)) }
                        CoreGroup(label: eff.isEmpty ? "Cores" : "Performance", cores: perf, tint: Theme.cpu).frame(width: unit * CGFloat(perf.count))
                    }
                }
                .frame(minHeight: 170, maxHeight: .infinity)
            }
        }
    }

    private var loadPanel: some View {
        ConsolePanel(title: "Load average", trailing: "\(detail.processCount) processes") {
            HStack(spacing: 10) {
                ForEach(Array(zip(["1 min", "5 min", "15 min"], detail.loadAverage + [0, 0, 0])), id: \.0) { label, value in
                    MiniStat(value: String(format: "%.2f", value), caption: label)
                }
                if let rpm = snap.thermals?.fanRPM.max() { MiniStat(value: "\(Int(rpm.rounded()))", caption: "fan rpm") }
            }
        }
    }

    private var enginePanel: some View {
        ConsolePanel(title: "Engine") {
            VStack(spacing: 14) {
                MeterRow(label: "Overall", fraction: snap.gpu, value: Fmt.percent(snap.gpu), tint: Theme.gpu)
                if let r = detail.gpuRenderer { MeterRow(label: "Renderer", fraction: r, value: Fmt.percent(r), tint: Theme.gpu) }
                if let t = detail.gpuTiler { MeterRow(label: "Tiler", fraction: t, value: Fmt.percent(t), tint: Theme.ice) }
            }
        }
    }

    @ViewBuilder private var gpuMemoryPanel: some View {
        if let used = detail.gpuMemoryInUse {
            let budget = detail.gpuWorkingSet > 0 ? detail.gpuWorkingSet : snap.memTotal
            ConsolePanel(title: "Graphics memory", trailing: detail.gpuMemoryAllocated.map { "\(Self.bytes($0)) allocated" }) {
                MeterRow(label: "In use", fraction: budget > 0 ? min(1, Double(used) / Double(budget)) : 0,
                         value: "\(Self.bytes(used)) of \(Self.bytes(budget))", tint: Theme.gpu)
            }
        }
    }

    private var gpuFacts: some View {
        ConsolePanel(title: "Details") {
            VStack(spacing: 2) {
                if !detail.gpuName.isEmpty { FactRow(icon: "cube.transparent", label: "Chip", value: detail.gpuName) }
                if detail.gpuCores > 0 { FactRow(icon: "square.grid.3x3", label: "GPU cores", value: "\(detail.gpuCores)") }
                if !detail.gpuFamily.isEmpty { FactRow(icon: "sparkles", label: "Graphics API", value: detail.gpuFamily) }
                if let w = snap.systemWatts { FactRow(icon: "bolt", label: "System draw", value: String(format: "%.1f W", w)) }
            }
        }
    }

    private var compositionPanel: some View {
        let parts: [(String, UInt64, Color)] = [
            ("App memory", detail.memApp, Theme.memory), ("Wired", detail.memWired, Theme.heat),
            ("Compressed", detail.memCompressed, Theme.netUp), ("Cached files", detail.memCached, Theme.disk), ("Free", detail.memFree, Theme.textFaint),
        ]
        let total = max(1, parts.reduce(UInt64(0)) { $0 + $1.1 })
        return ConsolePanel(title: "What's in memory") {
            VStack(spacing: 14) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.0) { p in
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(p.2.opacity(p.0 == "Free" ? 0.35 : 0.9))
                                .frame(width: max(2, (g.size.width - 8) * CGFloat(Double(p.1) / Double(total))))
                        }
                    }
                }
                .frame(height: 18)
                VStack(spacing: 2) {
                    ForEach(parts, id: \.0) { p in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(p.2.opacity(p.0 == "Free" ? 0.35 : 0.9)).frame(width: 12, height: 12)
                            Text(p.0).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(Self.bytes(p.1)).font(.readout(14, .semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        .frame(minHeight: 30, maxHeight: 52)
                    }
                }
            }
        }
    }

    private var swapPanel: some View {
        let level = detail.pressureLevel
        let (word, color): (String, Color) = level >= 4 ? ("Critical", Theme.critical) : level >= 2 ? ("Elevated", Theme.warning) : ("Normal", Theme.battery)
        return ConsolePanel(title: "Pressure and swap") {
            HStack(spacing: 10) {
                HStack(spacing: 8) { Lamp(color: color, on: true, size: 8); MiniStat(value: word, caption: "memory pressure", tint: color) }
                MiniStat(value: Self.bytes(detail.swapUsed), caption: detail.swapTotal > 0 ? "swap, of \(Self.bytes(detail.swapTotal))" : "swap used")
            }
        }
    }

    private var connectionPanel: some View {
        ConsolePanel(title: "Connection") {
            VStack(spacing: 2) {
                FactRow(icon: "wifi", label: "Wi-Fi", value: network.ssid ?? (detail.rssi != nil ? "Connected" : "Not on Wi-Fi"))
                if let rssi = detail.rssi { FactRow(icon: "cellularbars", label: "Signal", value: "\(rssi) dBm, \(Self.signalWord(rssi))") }
                if let rate = detail.txRateMbps, rate > 0 { FactRow(icon: "speedometer", label: "Link rate", value: "\(Int(rate)) Mbps") }
                if let router = detail.router { FactRow(icon: "wifi.router", label: "Router", value: router, copyable: true) }
                if let dns = detail.dns.first { FactRow(icon: "signpost.right", label: "DNS", value: dns, copyable: true) }
            }
        }
    }

    private var totalsPanel: some View {
        ConsolePanel(title: "Since startup", trailing: "up \(Fmt.uptime(snap.uptime))") {
            HStack(spacing: 10) {
                MiniStat(value: Self.bytes(detail.bytesIn), caption: "downloaded", tint: Theme.netDown)
                MiniStat(value: Self.bytes(detail.bytesOut), caption: "uploaded", tint: Theme.netUp)
            }
        }
    }

    private var interfacesPanel: some View {
        ConsolePanel(title: "Interfaces", trailing: detail.interfaces.isEmpty ? nil : "\(detail.interfaces.count) active") {
            VStack(spacing: 2) {
                ForEach(detail.interfaces.prefix(5)) { i in
                    FactRow(icon: i.name == detail.interface ? "arrow.up.arrow.down.circle.fill" : "circle.dotted",
                            label: "\(i.label)  \(i.name)", value: i.address,
                            tint: i.name == detail.interface ? Theme.netDown : Theme.textFaint, copyable: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Right: who, and what you can do about it

    @ViewBuilder private var right: some View {
        switch kind {
        case .cpu: ProcessTable(title: "Busiest processes", rows: processes, byMemory: false, tint: Theme.cpu)
        case .gpu: ProcessTable(title: "Most active processes", note: "macOS doesn't report GPU use per process", rows: processes, byMemory: false, tint: Theme.gpu)
        case .memory: ProcessTable(title: "Using the most memory", rows: processes, byMemory: true, tint: Theme.memory)
        case .network:
            VStack(spacing: 14) {
                ConsolePanel(title: "Addresses") {
                    VStack(spacing: 2) {
                        FactRow(icon: "network", label: "This Mac", value: network.localIP ?? "—", copyable: network.localIP != nil)
                        FactRow(icon: "globe", label: "Public", value: network.publicIP ?? (network.loading ? "Looking up…" : "Unavailable"), copyable: network.publicIP != nil)
                    }
                }
                interfacesPanel
            }
        }
    }

    // MARK: Formatting

    private static func bytes(_ b: UInt64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .memory; f.allowedUnits = [.useMB, .useGB, .useTB]
        return f.string(fromByteCount: Int64(min(b, UInt64(Int64.max))))
    }
    private static func signalWord(_ rssi: Int) -> String {
        rssi >= -55 ? "excellent" : rssi >= -67 ? "good" : rssi >= -75 ? "fair" : "weak"
    }
}

/// One group of cores as vertical segment meters.
private struct CoreGroup: View {
    let label: String
    let cores: [CoreLoad]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(cores) { core in
                    VStack(spacing: 3) {
                        ForEach((0..<12).reversed(), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Double(i) < (core.load * 12).rounded() ? Theme.pressure(core.load, base: tint) : Theme.trackFill)
                                .frame(maxWidth: 22, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text(label).font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                Spacer(minLength: 4)
                Text(Fmt.percent(cores.isEmpty ? 0 : cores.map(\.load).reduce(0, +) / Double(cores.count)))
                    .font(.readout(12, .semibold)).foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
