import SwiftUI

struct MetricDetail: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let history: [Double]
    let asPercent: Bool   // else treat values as bytes/sec
}

/// Large expanded view of a metric — a big history graph + now/avg/peak,
/// shown when a dashboard tile is tapped.
struct MetricDetailView: View {
    let detail: MetricDetail
    var onClose: () -> Void = {}

    private var current: Double { detail.history.last ?? 0 }
    private var avg: Double { detail.history.isEmpty ? 0 : detail.history.reduce(0, +) / Double(detail.history.count) }
    private var peak: Double { detail.history.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: detail.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(detail.color)
                Text(detail.title).font(.deck(24, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.textFaint)
                }.buttonStyle(.pressable)
            }
            Sparkline(values: detail.history, color: detail.color, fillOpacity: 0.22,
                      ceiling: detail.asPercent ? 1.0 : nil)
                .frame(maxWidth: .infinity).frame(height: 280)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
            HStack(spacing: 0) {
                stat("Now", current); divider; stat("Average", avg); divider; stat("Peak", peak)
            }
        }
        .padding(28)
        .frame(width: 980, height: 520)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(detail.color.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30)
    }

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(width: 1, height: 48) }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(format(value)).font(.readout(34, .bold)).foregroundStyle(detail.color)
            Text(label.uppercased()).font(.deck(11, .bold)).tracking(1.4).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private func format(_ v: Double) -> String {
        if detail.asPercent { return "\(Int((v * 100).rounded()))%" }
        let r = Fmt.rate(v); return r.value + r.unit
    }
}
