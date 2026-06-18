import SwiftUI

/// Minimal mode — mostly-black, just the time and a few vitals (OLED/battery
/// friendly). Tap anywhere to return to full.
struct MinimalView: View {
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 30) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 6) {
                        Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 150, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.9))
                        Text(ctx.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.deck(22, .medium)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                HStack(spacing: 46) {
                    stat("cpu.fill", Fmt.percent(metrics.snap.cpu), Theme.cpu)
                    stat("memorychip.fill", Fmt.percent(metrics.snap.memFraction), Theme.memory)
                    if let b = metrics.snap.battery {
                        stat(b.charging ? "bolt.fill" : "battery.100", Fmt.percent(b.level), Theme.battery)
                    }
                }
            }
            VStack {
                Spacer()
                Text("Tap anywhere to exit").font(.deck(13)).foregroundStyle(.white.opacity(0.22)).padding(.bottom, 26)
            }
        }
    }

    private func stat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(color.opacity(0.85))
            Text(value).font(.readout(28, .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Sleep mode — pure black with a very dim clock that drifts slowly to avoid
/// burn-in. Monitoring is stopped while here. Tap anywhere to wake.
struct SleepView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            GeometryReader { geo in
                let m = Calendar.current.component(.minute, from: ctx.date)
                let dx = CGFloat((m % 7) - 3) * 26
                let dy = CGFloat((m % 5) - 2) * 26
                ZStack {
                    Color.black
                    Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.13))
                        .position(x: geo.size.width / 2 + dx, y: geo.size.height / 2 + dy)
                }
            }
        }
        .ignoresSafeArea()
    }
}
