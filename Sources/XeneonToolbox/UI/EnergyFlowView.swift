import SwiftUI

/// The energy-distribution modal (opened from the Power tile): watts from the
/// wall flowing through the machine and fanning out — Sankey-style — to the
/// SoC's consumers, with the heaviest apps below. AlDente-inspired, drawn in
/// the deck's telemetry language.
struct EnergyFlowView: View {
    @ObservedObject var power: PowerTelemetry
    var topApps: [ProcRow] = []
    var onClose: () -> Void
    @State private var history: [Double] = []

    private struct Consumer: Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let watts: Double
    }

    private var consumers: [Consumer] {
        let s = power.snap
        var out: [Consumer] = [
            .init(id: "cpu", name: "CPU", icon: "cpu.fill", color: Theme.cpu, watts: s.cpu),
            .init(id: "gpu", name: "GPU", icon: "cube.transparent.fill", color: Theme.gpu, watts: s.gpu),
            .init(id: "mem", name: "Memory", icon: "memorychip.fill", color: Theme.memory, watts: s.memory),
            .init(id: "disp", name: "Displays", icon: "display", color: Theme.time, watts: s.displays),
            .init(id: "media", name: "Media", icon: "video.fill", color: Theme.netUp, watts: s.media),
            .init(id: "ane", name: "Neural", icon: "brain", color: Theme.disk, watts: s.neural),
        ].filter { $0.watts >= 0.05 }
        if let other = s.other, other > 0.2 {
            // Real but unmetered consumers: SSD, fans, USB devices & ports (the
            // Edge panel itself!), networking, Thunderbolt, PSU overhead.
            out.append(.init(id: "other", name: "SSD, fans, USB, rest", icon: "ellipsis", color: Theme.textFaint, watts: other))
        }
        return out
    }

    var body: some View {
        DetailShell(title: "Energy", icon: "bolt.fill", tint: Theme.battery, subtitle: summary, actions: actions, onClose: onClose) {
            if !power.warmedUp {
                // The SoC counters need two samples for a delta — briefly measuring.
                VStack(spacing: 14) {
                    DeckSpinner(size: 36)
                    Text("Measuring power…").font(.deck(16)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if power.snap.systemIn == nil && !power.snap.blocksAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.slash").font(.system(size: 40)).foregroundStyle(Theme.textFaint)
                    Text("Power telemetry isn't available on this Mac")
                        .font(.deck(16)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    flow.frame(maxWidth: .infinity, maxHeight: .infinity)
                    ProcessTable(title: "Using the most power", note: "ranked by processor use", rows: topApps, byMemory: false, tint: Theme.netUp)
                        .frame(width: 640)
                }
            }
        }
        .onReceive(power.$snap) { s in
            guard power.warmedUp else { return }
            history = Array((history + [s.wall ?? s.blocksTotal]).suffix(60))
        }
    }

    private var summary: String {
        let s = power.snap
        guard power.warmedUp else { return "Where the watts go, measured live" }
        guard let sys = s.systemIn else { return "The chip is using \(Self.watts(s.blocksTotal)) right now" }
        return s.external ? "Drawing \(Self.watts(sys)) from the wall" : "Drawing \(Self.watts(sys)) from the battery"
    }

    private var actions: [DetailAction] {
        let pane = power.snap.batteryInstalled ? "com.apple.Battery-Settings.extension" : "com.apple.Energy-Saver-Settings.extension"
        return [DetailAction(title: power.snap.batteryInstalled ? "Battery settings" : "Energy settings", icon: "gearshape.fill", tint: Theme.textSecondary) {
            if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
        }]
    }

    // MARK: - Flow diagram

    private var flow: some View {
        HStack(spacing: 0) {
            source.frame(width: 300)
            SankeyBands(consumers: consumers.map { ($0.color, $0.watts) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Rows spread evenly over the full height — the same slots the
            // Sankey bands aim at, so each band meets its row.
            VStack(spacing: 0) {
                ForEach(consumers) { c in
                    consumerRow(c).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 320)
        }
    }

    private var source: some View {
        let s = power.snap
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: s.wall == nil ? "cpu.fill" : "powerplug.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.battery)
                    Text(s.wall == nil ? "Chip total" : s.external ? "Wall" : "Battery").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                }
                Text(Self.watts(s.wall ?? s.blocksTotal)).font(.readout(44, .bold)).foregroundStyle(Theme.textPrimary)
                if s.wall == nil {
                    Text("This Mac doesn't report what it draws at the plug.")
                        .font(.deck(12)).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
                }
                if let loss = s.adapterLoss, loss >= 0.1 {
                    Text("adapter loses \(Self.watts(loss))").font(.deck(12)).foregroundStyle(Theme.textFaint)
                }
                if let sys = s.systemIn {
                    Text("system \(Self.watts(sys))").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.battery.opacity(0.35), lineWidth: 1))

            if s.batteryInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: s.charging ? "battery.100.bolt" : "battery.75")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.battery)
                        Text("Battery").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if let p = s.batteryPercent {
                            Text("\(p)%").font(.readout(15, .bold)).foregroundStyle(Theme.textPrimary)
                        }
                    }
                    if abs(s.batteryW) >= 0.1 {
                        Text(s.batteryW > 0 ? "charging at \(Self.watts(s.batteryW))"
                                            : "draining at \(Self.watts(-s.batteryW))")
                            .font(.deck(12, .semibold))
                            .foregroundStyle(s.batteryW > 0 ? Theme.battery : Theme.netUp)
                    } else {
                        Text("idle").font(.deck(12)).foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            }
            if history.count > 1 {
                ConsolePanel(title: "Last two minutes", trailing: "peak \(Self.watts(history.max() ?? 0))") {
                    Sparkline(values: history, color: Theme.battery, fillOpacity: 0.2, ceiling: (history.max() ?? 1) * 1.15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func consumerRow(_ c: Consumer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.color).frame(width: 24)
            Text(c.name).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(Self.watts(c.watts)).font(.readout(16, .bold)).foregroundStyle(c.color)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(c.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(c.color.opacity(0.25), lineWidth: 1))
    }

    private static func watts(_ w: Double) -> String {
        w >= 10 ? String(format: "%.0f W", w) : String(format: "%.1f W", w)
    }
}

/// The curved Sankey bands from the source spine to each consumer row.
private struct SankeyBands: View {
    let consumers: [(color: Color, watts: Double)]

    var body: some View {
        Canvas { ctx, size in
            let total = max(consumers.reduce(0) { $0 + $1.watts }, 0.001)
            let x0: CGFloat = 6, x1 = size.width - 6
            // Source spine: centred block whose height maps the summed watts.
            let spineH = min(size.height * 0.86, max(60, size.height * 0.7))
            let sTop = (size.height - spineH) / 2
            // Consumer slots: match the right-hand rows (evenly stacked).
            let n = CGFloat(consumers.count)
            let rowH = size.height / max(n, 1)

            var sy = sTop
            for (i, c) in consumers.enumerated() {
                let frac = c.watts / total
                let bandS = max(3, spineH * frac)                 // source thickness
                let bandT = max(3, min(rowH * 0.62, 34))           // target thickness
                let ty = rowH * CGFloat(i) + (rowH - bandT) / 2
                var p = Path()
                let cx = (x0 + x1) / 2
                p.move(to: CGPoint(x: x0, y: sy))
                p.addCurve(to: CGPoint(x: x1, y: ty),
                           control1: CGPoint(x: cx, y: sy),
                           control2: CGPoint(x: cx, y: ty))
                p.addLine(to: CGPoint(x: x1, y: ty + bandT))
                p.addCurve(to: CGPoint(x: x0, y: sy + bandS),
                           control1: CGPoint(x: cx, y: ty + bandT),
                           control2: CGPoint(x: cx, y: sy + bandS))
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(
                    Gradient(colors: [Theme.battery.opacity(0.25), c.color.opacity(0.65)]),
                    startPoint: CGPoint(x: x0, y: size.height / 2),
                    endPoint: CGPoint(x: x1, y: size.height / 2)))
                sy += bandS
            }
            // The spine itself.
            let spine = Path(roundedRect: CGRect(x: x0 - 4, y: sTop - 2, width: 8, height: (sy - sTop) + 4), cornerRadius: 4)
            ctx.fill(spine, with: .color(Theme.battery.opacity(0.7)))
        }
        .padding(.horizontal, 10)
    }
}
