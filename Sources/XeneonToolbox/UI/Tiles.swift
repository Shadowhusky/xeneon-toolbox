import SwiftUI

// MARK: - Clock

struct ClockTile: View {
    var uptime: TimeInterval
    var weather: Weather?
    var size: TileSize = .s

    private let hhmm = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    var body: some View {
        TileSurface(accent: Theme.time) {
            // Minute cadence: the tile shows HH:MM, so it must not re-lay-out
            // its whole content every second.
            TimelineView(.everyMinute) { context in
                let now = context.date
                switch size {
                case .t: tall(now)
                case .w, .l: wide(now)
                case .s: small(now)
                }
            }
        }
    }

    private func small(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(temp: true)
            Spacer()
            Text(now, format: .dateTime.weekday(.wide)).font(.deck(18, .medium)).foregroundStyle(Theme.textSecondary)
            Text(now, format: hhmm).font(.readout(66, .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(now, format: .dateTime.month(.wide).day()).font(.deck(16, .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            uptimeRow
        }
    }

    private func tall(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(temp: false)
            Spacer()
            Text(now, format: .dateTime.weekday(.wide)).font(.deck(22, .medium)).foregroundStyle(Theme.textSecondary)
            Text(now, format: hhmm).font(.readout(88, .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(now, format: .dateTime.month(.wide).day()).font(.deck(18, .medium)).foregroundStyle(Theme.textSecondary)
            Spacer().frame(height: 18)
            DayProgressBar(date: now)
            Spacer()
            if let w = weather { weatherBlock(w) } else { weatherPlaceholder }
            Spacer()
            uptimeRow
        }
    }

    private func wide(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(temp: false)
            Spacer()
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(now, format: .dateTime.weekday(.wide)).font(.deck(22, .medium)).foregroundStyle(Theme.textSecondary)
                    Text(now, format: hhmm).font(.readout(88, .bold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(now, format: .dateTime.month(.wide).day()).font(.deck(18, .medium)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if let w = weather { weatherBlock(w).frame(width: 220, alignment: .leading) }
            }
            Spacer()
            uptimeRow
        }
    }

    private func header(temp: Bool) -> some View {
        HStack {
            TileHeader(title: "Local", systemImage: "clock.fill", accent: Theme.time)
            if temp, let w = weather {
                HStack(spacing: 5) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).foregroundStyle(Theme.time)
                    Text(w.displayTemp).font(.readout(16, .bold)).foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    private func weatherBlock(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: w.symbol).font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.multicolor).foregroundStyle(Theme.disk)
                Text(w.displayTemp).font(.readout(42, .semibold)).foregroundStyle(Theme.textPrimary)
            }
            Text(w.condition).font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                if let hi = w.displayHigh, let lo = w.displayLow {
                    Text("H \(hi)  L \(lo)").font(.readout(13, .semibold)).foregroundStyle(Theme.textFaint)
                }
                if !w.city.isEmpty {
                    Text(w.city).font(.deck(13)).foregroundStyle(Theme.textFaint).lineLimit(1)
                }
            }
        }
    }

    private var weatherPlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud").font(.system(size: 22)).foregroundStyle(Theme.textFaint)
            Text("Weather loading…").font(.deck(14)).foregroundStyle(Theme.textFaint)
        }
    }

    private var uptimeRow: some View {
        HStack {
            Label("Uptime", systemImage: "power").font(.deck(13)).foregroundStyle(Theme.textFaint)
            Spacer()
            Text(Fmt.uptime(uptime)).font(.readout(14, .semibold)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Gauges

/// A ring gauge tile. Small: header, ring, footer. Wide: the ring on the left,
/// the history in a recessed well on the right.
struct GaugeTile<Footer: View>: View {
    let title: String
    let icon: String
    let accent: Color
    let value: Double
    let caption: String
    var available = true
    var size: TileSize = .s
    var history: [Double] = []
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        TileSurface(accent: accent) {
            if size.columns > 1 { wide } else { small }
        }
    }

    private var ring: some View {
        RingGauge(value: available ? value : 0, color: available ? accent : Theme.textFaint) {
            VStack(spacing: 2) {
                Text(available ? Fmt.percent(value) : "—")
                    .font(.readout(46, .bold)).foregroundStyle(available ? Theme.textPrimary : Theme.textFaint)
                Text(available ? caption : "n/a").font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            TileHeader(title: title, systemImage: icon, accent: accent)
            Spacer(minLength: 8)
            ring.frame(maxWidth: .infinity, maxHeight: .infinity)
            Spacer(minLength: 8)
            footer()
        }
    }

    private var wide: some View {
        VStack(alignment: .leading, spacing: 0) {
            TileHeader(title: title, systemImage: icon, accent: accent)
            Spacer(minLength: 10)
            HStack(spacing: 20) {
                ring.frame(maxHeight: .infinity)
                VStack(spacing: 10) {
                    Well {
                        Sparkline(values: history, color: accent, ceiling: 1)
                    }
                    .frame(maxHeight: .infinity)
                    footer()
                }
            }
        }
    }
}

struct CPUTile: View {
    var value: Double
    var history: [Double]
    var size: TileSize = .s
    var body: some View {
        GaugeTile(title: "Processor", icon: "cpu.fill", accent: Theme.pressure(value, base: Theme.cpu),
                  value: value, caption: "load", size: size, history: history) {
            if size.columns > 1 { HistoryStats(history: history, accent: Theme.cpu) }
            else { Well(inset: 8) { Sparkline(values: history, color: Theme.cpu).frame(height: 36) } }
        }
    }
}

struct GPUTile: View {
    var value: Double
    var history: [Double]
    var available = true
    var size: TileSize = .s
    var body: some View {
        GaugeTile(title: "Graphics", icon: "cube.transparent.fill", accent: Theme.gpu, value: value, caption: "gpu",
                  available: available, size: size, history: history) {
            if size.columns > 1 { HistoryStats(history: history, accent: Theme.gpu) }
            else { Well(inset: 8) { Sparkline(values: history, color: Theme.gpu).frame(height: 36) } }
        }
    }
}

struct MemoryTile: View {
    var snap: MetricsSnapshot
    var history: [Double] = []
    var size: TileSize = .s
    private var tint: Color { Theme.pressure(snap.memFraction, base: Theme.memory) }
    var body: some View {
        GaugeTile(title: "Memory", icon: "memorychip.fill", accent: tint,
                  value: snap.memFraction, caption: snap.memFraction > 0.9 ? "pressure" : "used",
                  size: size, history: history) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.gb(snap.memUsed)).font(.readout(26, .bold)).foregroundStyle(Theme.textPrimary)
                Text("/ \(Fmt.gb(snap.memTotal)) GB").font(.deck(15)).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
    }
}

/// Average and peak of a history, for wide gauge tiles.
struct HistoryStats: View {
    var history: [Double]
    var accent: Color
    var body: some View {
        let avg = history.isEmpty ? 0 : history.reduce(0, +) / Double(history.count)
        let peak = history.max() ?? 0
        HStack(spacing: 0) {
            stat("avg", avg); Rectangle().fill(Theme.stroke).frame(width: 1, height: 30); stat("peak", peak)
        }
    }
    private func stat(_ label: String, _ v: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.percent(v)).font(.readout(22, .bold)).foregroundStyle(accent)
            Text(label).font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Network

struct NetworkTile: View {
    var snap: MetricsSnapshot
    var rxHistory: [Double]
    var txHistory: [Double]
    var size: TileSize = .s

    var body: some View {
        TileSurface(accent: Theme.netDown) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Network", systemImage: "dot.radiowaves.up.forward", accent: Theme.netDown)
                Spacer(minLength: 10)
                if size.columns > 1 {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            rateRow(icon: "arrow.down", rate: snap.netRx, color: Theme.netDown, big: true)
                            rateRow(icon: "arrow.up", rate: snap.netTx, color: Theme.netUp, big: true)
                        }
                        .frame(width: 210, alignment: .leading)
                        Well { graphs }.frame(maxHeight: .infinity)
                    }
                } else {
                    rateRow(icon: "arrow.down", rate: snap.netRx, color: Theme.netDown, big: false)
                    Spacer().frame(height: 10)
                    rateRow(icon: "arrow.up", rate: snap.netTx, color: Theme.netUp, big: false)
                    Spacer(minLength: 8)
                    Well(inset: 8) { graphs.frame(height: 44) }
                }
            }
        }
    }

    private var graphs: some View {
        ZStack {
            Sparkline(values: rxHistory, color: Theme.netDown)
            Sparkline(values: txHistory, color: Theme.netUp)
        }
    }

    private func rateRow(icon: String, rate: Double, color: Color, big: Bool) -> some View {
        let r = Fmt.rate(rate)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(.system(size: big ? 17 : 14, weight: .bold)).foregroundStyle(color)
            Text(r.value).font(.readout(big ? 44 : 34, .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(r.unit).font(.deck(big ? 15 : 13)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Storage

struct StorageTile: View {
    var snap: MetricsSnapshot
    private var tint: Color { Theme.pressure(snap.diskUsedFraction, base: Theme.disk) }
    var body: some View {
        TileSurface(accent: tint) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Storage", systemImage: "internaldrive.fill", accent: tint)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.gb(snap.diskFree)).font(.readout(52, .bold)).foregroundStyle(Theme.textPrimary)
                    Text("GB free").font(.deck(17)).foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                CapacityBar(fraction: snap.diskUsedFraction, color: tint)
                Spacer().frame(height: 12)
                HStack {
                    Text(snap.diskUsedFraction > 0.9 ? "Low space" : "\(Fmt.percent(snap.diskUsedFraction)) used")
                        .font(.deck(13)).foregroundStyle(snap.diskUsedFraction > 0.9 ? Theme.critical : Theme.textFaint)
                    Spacer()
                    Text("\(Fmt.gb(snap.diskTotal)) GB total").font(.deck(13)).foregroundStyle(Theme.textFaint)
                }
            }
        }
    }
}

// MARK: - Power

struct PowerTile: View {
    var battery: BatteryInfo?
    var uptime: TimeInterval
    var systemWatts: Double? = nil
    var body: some View {
        TileSurface(accent: tint) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Power", systemImage: battery == nil ? "powerplug.fill" : "battery.100", accent: tint)
                Spacer(minLength: 8)
                if let b = battery {
                    RingGauge(value: b.level, color: tint) {
                        VStack(spacing: 2) {
                            Text(Fmt.percent(b.level)).font(.readout(46, .bold)).foregroundStyle(Theme.textPrimary)
                            Image(systemName: b.charging ? "bolt.fill" : "battery.50")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer(minLength: 8)
                    HStack { Text(statusText(b)).font(.deck(14)).foregroundStyle(Theme.textSecondary); Spacer() }
                } else if let w = systemWatts {
                    // Desktops: the live draw is the story — make it the hero.
                    Spacer()
                    VStack(spacing: 6) {
                        (Text(w >= 100 ? String(format: "%.0f", w) : String(format: "%.1f", w))
                            .font(.readout(54, .bold)).foregroundStyle(Theme.textPrimary)
                            + Text(" W").font(.readout(24, .bold)).foregroundStyle(tint))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text("System draw").font(.deck(13, .medium)).foregroundStyle(Theme.textFaint)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                    HStack {
                        Label("Uptime", systemImage: "power").font(.deck(13)).foregroundStyle(Theme.textFaint)
                        Spacer()
                        Text(Fmt.uptime(uptime)).font(.readout(14, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 50, weight: .semibold)).foregroundStyle(tint)
                            .deckGlow(tint, strength: 0.8)
                        Text("On wall power").font(.deck(17, .semibold)).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                    HStack {
                        Label("Uptime", systemImage: "power").font(.deck(13)).foregroundStyle(Theme.textFaint)
                        Spacer()
                        Text(Fmt.uptime(uptime)).font(.readout(14, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
    private var tint: Color {
        guard let b = battery else { return Theme.battery }
        return b.level < 0.2 && !b.charging ? Theme.batteryLow : Theme.battery
    }
    private func statusText(_ b: BatteryInfo) -> String {
        if b.charging { return "Charging" }
        if let m = b.minutesRemaining { return "\(m / 60)h \(m % 60)m remaining" }
        // macOS reports no estimate for a minute or two after unplugging.
        return "On battery · estimating…"
    }
}

struct ToggleDot: View {
    var on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Theme.accent.opacity(0.35) : Color.white.opacity(0.1))
                .frame(width: 54, height: 30)
            Circle().fill(on ? Theme.accent : Theme.textFaint)
                .frame(width: 24, height: 24).padding(3)
                .shadow(color: on ? Theme.accent.opacity(0.6) : .clear, radius: 6)
        }
        .animation(Motion.snappy, value: on)
    }
}
