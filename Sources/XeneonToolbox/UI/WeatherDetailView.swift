import SwiftUI
import ToolboxKit

/// Weather detail: current conditions on the left, the next hours and the week
/// on the right. Opened by tapping the Local or Weather tile.
struct WeatherDetailView: View {
    let weather: Weather?
    var loading = false
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text(weather.map { $0.city.isEmpty ? "Local weather" : $0.city } ?? "Weather")
                    .font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                CircleIconButton(icon: "xmark", size: 42, action: onClose)
            }
            if let w = weather {
                HStack(alignment: .top, spacing: 28) {
                    current(w).frame(width: 340, alignment: .leading)
                    VStack(alignment: .leading, spacing: 18) {
                        if !w.hours.isEmpty { hourly(w) }
                        forecast(w)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else if loading {
                VStack(spacing: 14) {
                    DeckSpinner(size: 36)
                    Text("Getting the forecast…").font(.deck(16)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cloud.slash").font(.system(size: 40)).foregroundStyle(Theme.textFaint)
                    Text("Weather unavailable").font(.deck(18)).foregroundStyle(Theme.textSecondary)
                    Text("Check your connection. The forecast retries on its own.")
                        .font(.deck(13)).foregroundStyle(Theme.textFaint)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .frame(width: 1240, height: 470)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
        .bezel(corner: 28, tint: Theme.ice)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
    }

    private func current(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: w.symbol).font(.system(size: 64, weight: .medium))
                    .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice)
                    .frame(width: 84, height: 84)
                Text(w.displayTemp).font(.hero(96)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(w.condition).font(.deck(20, .medium)).foregroundStyle(Theme.textSecondary)
                if let hi = w.displayHigh, let lo = w.displayLow {
                    Text("H \(hi)   L \(lo)").font(.readout(16, .semibold)).foregroundStyle(Theme.textFaint)
                }
            }
            HStack(spacing: 10) {
                chip("humidity.fill", w.humidity.map { "\($0)%" } ?? "—", "Humidity")
                chip("wind", w.displayWind ?? "—", "Wind")
            }
        }
    }

    private func chip(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textFaint)
            Text(value).font(.readout(15, .semibold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.deck(13)).foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(Capsule().fill(Theme.wellFill))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
    }

    private func hourly(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next 12 hours").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
            Well {
                HStack(spacing: 0) {
                    ForEach(w.hours) { h in
                        VStack(spacing: 7) {
                            Text(h.hourLabel).font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                            Image(systemName: h.symbol).font(.system(size: 20, weight: .medium))
                                .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice).frame(height: 24)
                            Text(h.temp()).font(.readout(15, .semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func forecast(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(w.days) { d in
                    VStack(spacing: 10) {
                        Text(d.weekday).font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                        Image(systemName: d.symbol).font(.system(size: 26, weight: .medium))
                            .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice).frame(height: 30)
                        HStack(spacing: 6) {
                            Text(d.high()).font(.readout(16, .semibold)).foregroundStyle(Theme.textPrimary)
                            Text(d.low()).font(.readout(16, .medium)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                }
            }
        }
    }
}
