import SwiftUI

enum ProcessMetric {
    case cpu, mem, active   // active = "most active" (by CPU), used for GPU where per-process isn't available
    var title: String {
        switch self {
        case .cpu: return "Top processes · CPU"
        case .mem: return "Top processes · Memory"
        case .active: return "Most active processes"
        }
    }
    var byMemory: Bool { self == .mem }
    func value(_ r: ProcRow) -> Double { byMemory ? r.mem : r.cpu }
}

struct MetricDetail: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let history: [Double]
    let asPercent: Bool          // else treat values as bytes/sec
    var processMetric: ProcessMetric? = nil
}

/// Connection facts for the Network detail.
struct NetworkInfo: Equatable {
    var ssid: String?
    var localIP: String?
    var publicIP: String?
    var loading = true
}

/// Large expanded view of a metric: a history graph + now/avg/peak, and — for
/// CPU/GPU/Memory — a ranking of the processes using that resource.
struct MetricDetailView: View {
    let detail: MetricDetail
    var processes: [ProcRow] = []
    var network: NetworkInfo? = nil
    var onClose: () -> Void = {}

    private var current: Double { detail.history.last ?? 0 }
    private var avg: Double { detail.history.isEmpty ? 0 : detail.history.reduce(0, +) / Double(detail.history.count) }
    private var peak: Double { detail.history.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: detail.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(detail.color)
                Text(detail.title).font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                CircleIconButton(icon: "xmark", size: 42, action: onClose)
            }

            if detail.processMetric != nil {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 16) { graph; stats }.frame(maxWidth: .infinity)
                    processList.frame(width: 380)
                }
            } else if let network {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 16) { graph; stats }.frame(maxWidth: .infinity)
                    connection(network).frame(width: 340)
                }
            } else {
                graph.frame(height: 280)
                stats
            }
        }
        .padding(28)
        .frame(width: 980, height: 520)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
        .bezel(corner: 24, tint: detail.color)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
    }

    private var graph: some View {
        Sparkline(values: detail.history, color: detail.color, fillOpacity: 0.22,
                  ceiling: detail.asPercent ? 1.0 : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat("Now", current); divider; stat("Average", avg); divider; stat("Peak", peak)
        }
    }

    @ViewBuilder private var processList: some View {
        let metric = detail.processMetric ?? .cpu
        let isMem = metric.byMemory
        let maxRSS = max(1, processes.map(\.rssMB).max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            Text(metric.title).font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
            if processes.isEmpty {
                Text("Reading processes…").font(.deck(14)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(processes.prefix(9)) { r in
                    let frac = isMem ? min(1, r.rssMB / maxRSS) : min(1, r.cpu / 100)
                    HStack(spacing: 12) {
                        Text(r.name).font(.deck(14, .medium)).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).frame(width: 142, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(LinearGradient(colors: [detail.color.opacity(0.7), detail.color],
                                                              startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, g.size.width * frac))
                            }
                        }
                        .frame(height: 10)
                        Text(isMem ? Self.memSize(r.rssMB) : "\(Int(r.cpu.rounded()))%")
                            .font(.readout(14, .bold)).foregroundStyle(detail.color)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .frame(height: 26)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func connection(_ n: NetworkInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
            infoRow("wifi", "Wi-Fi", n.ssid ?? "Not on Wi-Fi")
            infoRow("network", "Local IP", n.localIP ?? "—")
            infoRow("globe", "Public IP", n.publicIP ?? (n.loading ? "Looking up…" : "Unavailable"))
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(detail.color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.deck(12, .semibold)).foregroundStyle(Theme.textFaint)
                Text(value).font(.readout(16, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private static func memSize(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(width: 1, height: 48) }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(format(value)).font(.readout(34, .bold)).foregroundStyle(detail.color)
            Text(label).font(.deck(12, .semibold)).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private func format(_ v: Double) -> String {
        if detail.asPercent { return "\(Int((v * 100).rounded()))%" }
        let r = Fmt.rate(v); return r.value + r.unit
    }
}
