import SwiftUI

private let ringSize: CGFloat = 176

struct ClockTile: View {
    var uptime: TimeInterval
    var body: some View {
        TileSurface(accent: Theme.accent) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(title: "Local", systemImage: "clock.fill", accent: Theme.accent)
                    Spacer()
                    Text(now, format: .dateTime.weekday(.wide))
                        .font(.deck(22, .medium)).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.readout(74, .bold)).foregroundStyle(Theme.textPrimary)
                        Text(now, format: .dateTime.second(.twoDigits))
                            .font(.readout(26, .semibold)).foregroundStyle(Theme.accent)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer()
                    HStack {
                        Text(now, format: .dateTime.month(.wide).day())
                            .font(.deck(17, .medium)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("UP \(Fmt.uptime(uptime))")
                            .font(.deck(13, .semibold)).tracking(0.5).foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
    }
}

struct GaugeTile: View {
    let title: String
    let icon: String
    let accent: Color
    let value: Double
    let caption: String
    @ViewBuilder var footer: () -> AnyView

    var body: some View {
        TileSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: title, systemImage: icon, accent: accent)
                Spacer()
                RingGauge(value: value, color: accent) {
                    VStack(spacing: 2) {
                        Text(Fmt.percent(value)).font(.readout(42, .bold)).foregroundStyle(Theme.textPrimary)
                        Text(caption).font(.deck(11, .bold)).tracking(1.6).foregroundStyle(Theme.textFaint)
                    }
                }
                .frame(width: ringSize, height: ringSize)
                .frame(maxWidth: .infinity)
                Spacer()
                footer()
            }
        }
    }
}

struct CPUTile: View {
    var value: Double
    var history: [Double]
    var body: some View {
        GaugeTile(title: "Processor", icon: "cpu.fill", accent: Theme.cpu, value: value, caption: "LOAD") {
            AnyView(Sparkline(values: history, color: Theme.cpu).frame(height: 48))
        }
    }
}

struct MemoryTile: View {
    var snap: MetricsSnapshot
    var body: some View {
        GaugeTile(title: "Memory", icon: "memorychip.fill", accent: Theme.memory, value: snap.memFraction, caption: "USED") {
            AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.gb(snap.memUsed)).font(.readout(26, .bold)).foregroundStyle(Theme.textPrimary)
                    Text("/ \(Fmt.gb(snap.memTotal)) GB").font(.deck(15)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            )
        }
    }
}

struct NetworkTile: View {
    var snap: MetricsSnapshot
    var rxHistory: [Double]
    var txHistory: [Double]
    var body: some View {
        TileSurface(accent: Theme.netDown) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Network", systemImage: "dot.radiowaves.up.forward", accent: Theme.netDown)
                Spacer()
                rateRow(icon: "arrow.down", rate: snap.netRx, color: Theme.netDown)
                Spacer().frame(height: 18)
                rateRow(icon: "arrow.up", rate: snap.netTx, color: Theme.netUp)
                Spacer()
                ZStack {
                    Sparkline(values: rxHistory, color: Theme.netDown)
                    Sparkline(values: txHistory, color: Theme.netUp)
                }
                .frame(height: 56)
            }
        }
    }
    private func rateRow(icon: String, rate: Double, color: Color) -> some View {
        let r = Fmt.rate(rate)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(color)
            Text(r.value).font(.readout(34, .bold)).foregroundStyle(Theme.textPrimary)
            Text(r.unit).font(.deck(15)).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct StorageTile: View {
    var snap: MetricsSnapshot
    var body: some View {
        TileSurface(accent: Theme.disk) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Storage", systemImage: "internaldrive.fill", accent: Theme.disk)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.gb(snap.diskFree)).font(.readout(58, .bold)).foregroundStyle(Theme.textPrimary)
                    Text("GB free").font(.deck(18)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                CapacityBar(fraction: snap.diskUsedFraction, color: Theme.disk)
                Spacer().frame(height: 12)
                HStack {
                    Text("\(Fmt.percent(snap.diskUsedFraction)) used").font(.deck(13)).foregroundStyle(Theme.textFaint)
                    Spacer()
                    Text("\(Fmt.gb(snap.diskTotal)) GB total").font(.deck(13)).foregroundStyle(Theme.textFaint)
                }
            }
        }
    }
}

struct PowerTile: View {
    var battery: BatteryInfo?
    var uptime: TimeInterval
    var body: some View {
        TileSurface(accent: tint) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Power", systemImage: battery == nil ? "powerplug.fill" : "battery.100", accent: tint)
                Spacer()
                if let b = battery {
                    RingGauge(value: b.level, color: tint) {
                        VStack(spacing: 2) {
                            Text(Fmt.percent(b.level)).font(.readout(40, .bold)).foregroundStyle(Theme.textPrimary)
                            Image(systemName: b.charging ? "bolt.fill" : "battery.50")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                        }
                    }
                    .frame(width: ringSize, height: ringSize)
                    .frame(maxWidth: .infinity)
                    Spacer()
                    HStack { Text(statusText(b)).font(.deck(15)).foregroundStyle(Theme.textSecondary); Spacer() }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 58, weight: .semibold)).foregroundStyle(tint)
                            .shadow(color: tint.opacity(0.5), radius: 12)
                        Text("AC POWER").font(.deck(20, .bold)).tracking(2).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                    HStack {
                        Label("Uptime", systemImage: "power").font(.deck(14)).foregroundStyle(Theme.textFaint)
                        Spacer()
                        Text(Fmt.uptime(uptime)).font(.readout(16, .semibold)).foregroundStyle(Theme.textSecondary)
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
        return "On battery"
    }
}

struct ControlsTile: View {
    var touchOn: Bool
    var edgeDetected: Bool
    var toggleTouch: () -> Void
    var minimize: () -> Void

    var body: some View {
        TileSurface(accent: touchOn ? Theme.accent : Theme.textFaint) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Controls", systemImage: "slider.horizontal.3", accent: touchOn ? Theme.accent : Theme.textFaint)
                Spacer()
                Button(action: toggleTouch) {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(touchOn ? Theme.accent : Theme.textFaint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Touch").font(.deck(21, .semibold)).foregroundStyle(Theme.textPrimary)
                            Text(touchOn ? "Active" : "Off").font(.deck(13))
                                .foregroundStyle(touchOn ? Theme.accent : Theme.textFaint)
                        }
                        Spacer()
                        ToggleDot(on: touchOn)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 14)
                Label(edgeDetected ? "Edge connected" : "Edge not detected",
                      systemImage: edgeDetected ? "checkmark.circle.fill" : "questionmark.circle")
                    .font(.deck(13)).foregroundStyle(edgeDetected ? Theme.battery : Theme.textFaint)
                Spacer()
                Button(action: minimize) {
                    Label("Minimize", systemImage: "rectangle.compress.vertical")
                        .font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }
}
