import SwiftUI

struct ClockAppView: View {
    var body: some View {
        HStack(spacing: Theme.tileGap) {
            NowCard()
            WorldClocksCard()
                .frame(maxWidth: 460)
            FocusTimerCard()
                .frame(maxWidth: 460)
        }
    }
}

private struct NowCard: View {
    var body: some View {
        TileSurface(accent: Theme.accent) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let now = ctx.date
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(title: "Now", systemImage: "clock.fill", accent: Theme.accent)
                    Spacer()
                    Text(now, format: .dateTime.weekday(.wide))
                        .font(.deck(28, .medium)).foregroundStyle(Theme.textSecondary)
                    Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                        .font(.readout(120, .bold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Spacer()
                    Text(now, format: .dateTime.month(.wide).day().year())
                        .font(.deck(20, .medium)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

private struct WorldClocksCard: View {
    private let zones: [(String, String)] = [
        ("San Francisco", "America/Los_Angeles"),
        ("New York", "America/New_York"),
        ("London", "Europe/London"),
        ("Tokyo", "Asia/Tokyo"),
    ]
    var body: some View {
        TileSurface(accent: Theme.memory) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "World", systemImage: "globe", accent: Theme.memory)
                Spacer(minLength: 12)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 0) {
                        ForEach(zones, id: \.0) { city, tz in
                            row(city: city, tz: tz, now: ctx.date)
                            if city != zones.last?.0 { Divider().overlay(Theme.stroke) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func row(city: String, tz: String, now: Date) -> some View {
        HStack {
            Text(city).font(.deck(18, .medium)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                .timeZone()).environment(\.timeZone, TimeZone(identifier: tz) ?? .current)
                .font(.readout(24, .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 13)
    }
}

private struct FocusTimerCard: View {
    @State private var total = 25 * 60
    @State private var remaining = 25 * 60
    @State private var running = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        TileSurface(accent: Theme.netUp) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Focus", systemImage: "timer", accent: Theme.netUp)
                Spacer()
                ZStack {
                    RingGauge(value: total == 0 ? 0 : Double(total - remaining) / Double(total), color: Theme.netUp) {
                        Text(clock).font(.readout(40, .bold)).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 188, height: 188)
                }
                .frame(maxWidth: .infinity)
                Spacer()
                HStack(spacing: 8) {
                    ForEach([15, 25, 45], id: \.self) { mins in
                        preset(mins)
                    }
                }
                Spacer().frame(height: 12)
                HStack(spacing: 12) {
                    control(running ? "Pause" : "Start", icon: running ? "pause.fill" : "play.fill", accent: true) {
                        running.toggle()
                    }
                    control("Reset", icon: "arrow.counterclockwise", accent: false) {
                        running = false; remaining = total
                    }
                }
            }
        }
        .onReceive(tick) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { running = false; NSSound.beep() }
        }
    }
    private var clock: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    private func preset(_ mins: Int) -> some View {
        let selected = total == mins * 60
        return Button {
            total = mins * 60; remaining = mins * 60; running = false
        } label: {
            Text("\(mins)m").font(.deck(15, .semibold))
                .foregroundStyle(selected ? Theme.netUp : Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Theme.netUp.opacity(0.16) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Theme.netUp.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
    private func control(_ title: String, icon: String, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.deck(16, .semibold))
                .foregroundStyle(accent ? Theme.netUp : Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent ? Theme.netUp.opacity(0.16) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}
