import SwiftUI
import ToolboxKit

/// The weather console: now on the left, the next day as a temperature curve in
/// the middle, the week as range bars on the right. Opened from the Local or
/// Weather tile.
struct WeatherDetailView: View {
    @ObservedObject var service: WeatherService
    var onClose: () -> Void
    @State private var choosingCity = false
    @State private var refreshing = false

    private var weather: Weather? { service.weather }

    var body: some View {
        DetailShell(title: weather.map { $0.city.isEmpty ? "Local weather" : $0.city } ?? "Weather",
                    icon: "cloud.sun.fill", tint: Theme.ice,
                    subtitle: weather.map { "\($0.condition), feels like \(($0.feelsLikeC ?? $0.tempC).asTemp)" },
                    actions: actions, onClose: onClose) {
            if let w = weather {
                HStack(alignment: .top, spacing: 16) {
                    now(w).frame(width: 440).frame(maxHeight: .infinity, alignment: .top)
                    ConsolePanel(title: "Next 24 hours", trailing: "rain chance below") { HourlyChart(hours: w.hours) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Group {
                        if choosingCity {
                            ConsolePanel(title: "Location") { WeatherLocationPicker(weather: service) }
                        } else {
                            ConsolePanel(title: "This week") { WeekList(days: w.days) }
                        }
                    }
                    .frame(width: 600).frame(maxHeight: .infinity, alignment: .top)
                }
            } else if !service.firstAttemptDone {
                VStack(spacing: 14) {
                    DeckSpinner(size: 36)
                    Text("Getting the forecast…").font(.deck(16)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cloud.slash").font(.system(size: 40)).foregroundStyle(Theme.textFaint)
                    Text("Weather unavailable").font(.deck(18)).foregroundStyle(Theme.textSecondary)
                    Text("Check your connection. The forecast retries on its own.").font(.deck(13)).foregroundStyle(Theme.textFaint)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var actions: [DetailAction] {
        [DetailAction(title: refreshing ? "Refreshing" : "Refresh", icon: "arrow.clockwise", tint: Theme.textSecondary) {
            guard !refreshing else { return }
            refreshing = true
            Task { await service.refresh(); refreshing = false }
        },
        DetailAction(title: choosingCity ? "Show the week" : "Change city", icon: choosingCity ? "calendar" : "location.fill", tint: Theme.textSecondary) {
            withAnimation(Motion.smooth) { choosingCity.toggle() }
        }]
    }

    private func now(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: w.symbol).font(.system(size: 76, weight: .medium))
                    .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice).frame(width: 100, height: 96)
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.displayTemp).font(.hero(104)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if let hi = w.displayHigh, let lo = w.displayLow {
                        Text("High \(hi)   Low \(lo)").font(.readout(15, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            ConsolePanel(title: "Right now") {
                VStack(spacing: 2) {
                    FactRow(icon: "thermometer.medium", label: "Feels like", value: (w.feelsLikeC ?? w.tempC).asTemp)
                    FactRow(icon: "humidity.fill", label: "Humidity", value: w.humidity.map { "\($0)%" } ?? "—")
                    FactRow(icon: "wind", label: "Wind", value: w.displayWind ?? "—")
                    FactRow(icon: "sun.max", label: "UV index", value: w.uvIndex.map { "\(Int($0.rounded())), \(Self.uvWord($0))" } ?? "—")
                    FactRow(icon: "cloud.rain", label: "Rain today", value: w.days.first?.rainChance.map { "\($0)%" } ?? "—")
                    FactRow(icon: "sunrise", label: "Sunrise and sunset", value: Self.sunTimes(w))
                }
            }
        }
    }

    private static func uvWord(_ uv: Double) -> String {
        uv < 3 ? "low" : uv < 6 ? "moderate" : uv < 8 ? "high" : uv < 11 ? "very high" : "extreme"
    }

    private static func sunTimes(_ w: Weather) -> String {
        guard let up = w.sunrise, let down = w.sunset else { return "—" }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return "\(f.string(from: up))  to  \(f.string(from: down))"
    }
}

private extension Double {
    var asTemp: String { Weather.temp(self) }
}

/// A day of temperature as one line, with the sky above it and the chance of
/// rain as bars beneath.
private struct HourlyChart: View {
    let hours: [HourForecast]

    var body: some View {
        if hours.count < 2 {
            Text("Hourly forecast unavailable").font(.deck(14)).foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let temps = hours.map(\.tempC), lo = (temps.min() ?? 0) - 1, hi = (temps.max() ?? 1) + 1
                let step = geo.size.width / CGFloat(hours.count)
                let top: CGFloat = 78, bottom = geo.size.height - 74
                let point = { (i: Int) -> CGPoint in
                    CGPoint(x: step * (CGFloat(i) + 0.5), y: bottom - CGFloat((temps[i] - lo) / max(0.1, hi - lo)) * (bottom - top))
                }
                ZStack(alignment: .topLeading) {
                    Self.curve(count: hours.count, point: point, closedTo: bottom + 8)
                        .fill(LinearGradient(colors: [Theme.ice.opacity(0.22), Theme.ice.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Self.curve(count: hours.count, point: point, closedTo: nil)
                        .stroke(Theme.ice, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    ForEach(hours.indices, id: \.self) { i in
                        let p = point(i), labelled = i % 2 == 0
                        if labelled {
                            VStack(spacing: 4) {
                                Image(systemName: hours[i].symbol).font(.system(size: 17, weight: .medium))
                                    .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice).frame(height: 22)
                                Text(hours[i].temp()).font(.readout(14, .semibold)).foregroundStyle(Theme.textPrimary)
                            }
                            .position(x: p.x, y: 28)
                            Circle().fill(Theme.background).frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(Theme.ice, lineWidth: 2)).position(p)
                            Text(i == 0 ? "Now" : hours[i].hourLabel).font(.deck(12, .medium))
                                .foregroundStyle(i == 0 ? Theme.accent : Theme.textFaint)
                                .position(x: p.x, y: geo.size.height - 10)
                        }
                        let chance = CGFloat(hours[i].rainChance ?? 0) / 100
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.cpu.opacity(chance > 0.05 ? 0.3 + 0.6 * chance : 0.08))
                            .frame(width: max(6, step - 8), height: max(3, 34 * chance))
                            .position(x: p.x, y: geo.size.height - 28 - max(3, 34 * chance) / 2)
                    }
                }
            }
        }
    }

    /// A smooth line through the hours (Catmull-Rom as Béziers).
    private static func curve(count: Int, point: (Int) -> CGPoint, closedTo baseline: CGFloat?) -> Path {
        var path = Path()
        let pts = (0..<count).map(point)
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        if let baseline {
            path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: baseline))
            path.addLine(to: CGPoint(x: pts[0].x, y: baseline))
            path.closeSubpath()
        }
        return path
    }
}

/// The week as rows: each day's range drawn on the week's own scale.
private struct WeekList: View {
    let days: [DayForecast]

    var body: some View {
        let lo = days.map(\.lowC).min() ?? 0, hi = days.map(\.highC).max() ?? 1
        VStack(spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                HStack(spacing: 12) {
                    Text(i == 0 ? "Today" : d.weekday).font(.deck(15, .semibold))
                        .foregroundStyle(i == 0 ? Theme.textPrimary : Theme.textSecondary).frame(width: 58, alignment: .leading)
                    Image(systemName: d.symbol).font(.system(size: 19, weight: .medium))
                        .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice).frame(width: 30)
                    Text(d.rainChance.map { $0 >= 10 ? "\($0)%" : "" } ?? "").font(.readout(12, .semibold))
                        .foregroundStyle(Theme.cpu).frame(width: 40, alignment: .leading)
                    Text(d.low()).font(.readout(15, .medium)).foregroundStyle(Theme.textFaint).frame(width: 40, alignment: .trailing)
                    GeometryReader { g in
                        let span = max(0.1, hi - lo)
                        let x0 = CGFloat((d.lowC - lo) / span) * g.size.width, x1 = CGFloat((d.highC - lo) / span) * g.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.trackFill)
                            Capsule().fill(LinearGradient(colors: [Theme.ice, Theme.accent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, x1 - x0)).offset(x: x0)
                        }
                    }
                    .frame(height: 8)
                    Text(d.high()).font(.readout(15, .semibold)).foregroundStyle(Theme.textPrimary).frame(width: 40, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
