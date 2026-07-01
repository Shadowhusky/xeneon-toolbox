import SwiftUI
import ToolboxKit

/// Weather detail: current conditions plus a several-day forecast. Opened by
/// tapping the Local tile on the dashboard.
struct WeatherDetailView: View {
    let weather: Weather?
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let w = weather { current(w); Spacer(minLength: 0); forecast(w) }
            else {
                VStack(spacing: 12) {
                    Image(systemName: "cloud.slash").font(.system(size: 40)).foregroundStyle(Theme.textFaint)
                    Text("Weather unavailable").font(.deck(18)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(30)
        .frame(width: 920, height: 470)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))).contentShape(Circle())
            }.buttonStyle(.pressable).padding(18)
        }
    }

    private func current(_ w: Weather) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(w.city.isEmpty ? "Local weather" : w.city).font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(w.displayTemp).font(.readout(92, .medium)).foregroundStyle(Theme.textPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(w.condition).font(.deck(20, .medium)).foregroundStyle(Theme.textSecondary)
                        if let hi = w.displayHigh, let lo = w.displayLow {
                            Text("H:\(hi)   L:\(lo)").font(.readout(16, .semibold)).foregroundStyle(Theme.textFaint)
                        }
                    }
                }
                HStack(spacing: 12) {
                    chip("humidity.fill", w.humidity.map { "\($0)%" } ?? "—", "Humidity")
                    chip("wind", w.displayWind ?? "—", "Wind")
                }.padding(.top, 4)
            }
            Spacer()
            Image(systemName: w.symbol).font(.system(size: 84, weight: .medium))
                .symbolRenderingMode(.multicolor).foregroundStyle(Theme.disk)
                .padding(.top, 6)
        }
    }

    private func chip(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textFaint)
            Text(value).font(.readout(15, .bold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.deck(13)).foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func forecast(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORECAST").font(.deckLabel).tracking(Theme.labelTracking).foregroundStyle(Theme.textFaint)
            HStack(spacing: 0) {
                ForEach(w.days) { d in
                    VStack(spacing: 12) {
                        Text(d.weekday).font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                        Image(systemName: d.symbol).font(.system(size: 26, weight: .medium))
                            .symbolRenderingMode(.multicolor).foregroundStyle(Theme.disk).frame(height: 30)
                        HStack(spacing: 6) {
                            Text(d.high()).font(.readout(16, .bold)).foregroundStyle(Theme.textPrimary)
                            Text(d.low()).font(.readout(16, .semibold)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}
