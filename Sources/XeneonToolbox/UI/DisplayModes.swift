import SwiftUI
import ToolboxKit

/// Minimal mode — mostly-black ambient screen composed for the Edge's ultrawide
/// format: the clock reads as the hero on the left, vitals and the next reminder
/// sit in a quiet right-hand column. Tap anywhere to return to full.
struct MinimalView: View {
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var todos: TodoStore
    @ObservedObject var media: MediaController
    var weather: Weather? = nil
    var showNowPlaying = true
    var onHideNowPlaying: () -> Void = {}

    private var nextReminder: TodoItem? {
        todos.items.filter { !$0.done && $0.dueAt != nil }
            .min { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }
    private var openCount: Int { todos.items.filter { !$0.done }.count }

    private var playing: Bool { showNowPlaying && media.available && media.nowPlaying != nil }

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 0) {
                // Clock + vitals centre in whatever height is left above the player.
                HStack(spacing: 0) {
                    clockBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 110)

                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Theme.stroke, Theme.stroke, .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 1).padding(.vertical, 64)

                    rightColumn
                        .frame(width: 540)
                        .padding(.horizontal, 64)
                }
                .frame(maxHeight: .infinity)

                if playing {
                    NowPlayingBar(media: media, onHide: onHideNowPlaying)
                        .padding(.horizontal, 96)
                        .padding(.bottom, 12)
                }
                Text("Tap anywhere to exit")
                    .font(.deck(13)).foregroundStyle(.white.opacity(0.22)).padding(.bottom, 22)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playing)
    }

    private var clockBlock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 6) {
                Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.readout(176, .medium)).tracking(-3)
                    .foregroundStyle(.white.opacity(0.88))
                Text(ctx.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.deck(27, .medium)).foregroundStyle(.white.opacity(0.42))
                    .padding(.leading, 4)
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let w = weather { weatherLine(w) }
            vital("cpu.fill", Fmt.percent(metrics.snap.cpu), "CPU", Theme.cpu)
            vital("memorychip.fill", Fmt.percent(metrics.snap.memFraction), "MEM", Theme.memory)
            if let b = metrics.snap.battery {
                let low = b.level < 0.2 && !b.charging
                vital(b.charging ? "bolt.fill" : (low ? "battery.25" : "battery.100"),
                      Fmt.percent(b.level), "BATT", low ? Theme.batteryLow : Theme.battery)
            }
            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 4)
            reminderLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weatherLine(_ w: Weather) -> some View {
        HStack(spacing: 16) {
            Image(systemName: w.symbol).font(.system(size: 26, weight: .bold))
                .symbolRenderingMode(.multicolor).foregroundStyle(Theme.disk.opacity(0.85)).frame(width: 34)
            Text(w.displayTemp).font(.readout(42, .semibold)).foregroundStyle(.white.opacity(0.92))
                .frame(width: 132, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.condition).font(.deck(15, .semibold)).foregroundStyle(.white.opacity(0.5))
                if !w.city.isEmpty { Text(w.city).font(.deck(12)).foregroundStyle(.white.opacity(0.28)) }
            }
            Spacer(minLength: 0)
        }
    }

    private func vital(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 26, weight: .bold))
                .foregroundStyle(color.opacity(0.6)).frame(width: 34)
            Text(value).font(.readout(42, .semibold)).foregroundStyle(color.opacity(0.92))
                .frame(width: 132, alignment: .leading)
            Text(label).font(.deck(13, .bold)).tracking(1.8).foregroundStyle(.white.opacity(0.30))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var reminderLine: some View {
        if let r = nextReminder, let due = r.dueAt {
            let overdue = r.isOverdue
            let color = overdue ? Theme.batteryLow : Theme.netUp
            HStack(spacing: 11) {
                Image(systemName: overdue ? "exclamationmark.circle.fill" : "bell.fill").font(.system(size: 16))
                Text("\(r.title) · \(Self.time(due))").font(.deck(18, .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color.opacity(overdue ? 0.95 : 0.8))
        } else if openCount > 0 {
            HStack(spacing: 11) {
                Image(systemName: "checklist").font(.system(size: 16))
                Text("\(openCount) task\(openCount == 1 ? "" : "s") open").font(.deck(18, .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.4))
        } else {
            HStack(spacing: 11) {
                Text("All clear").font(.deck(18, .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.30))
        }
    }

    private static func time(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) { f.dateFormat = "h:mm a" }
        else if cal.isDateInTomorrow(d) { f.dateFormat = "'tmrw' h:mm a" }
        else { f.dateFormat = "EEE h:mm a" }
        return f.string(from: d)
    }
}

/// Sleep mode — pure black with a very dim clock that drifts slowly and smoothly
/// to avoid burn-in. Monitoring is stopped while here. Tap anywhere to wake.
struct SleepView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 12)) { ctx in
            GeometryReader { geo in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let dx = CGFloat(sin(t / 47)) * geo.size.width * 0.17
                let dy = CGFloat(cos(t / 61)) * geo.size.height * 0.22
                ZStack {
                    Color.black
                    Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 60, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.12))
                        .position(x: geo.size.width / 2 + dx, y: geo.size.height / 2 + dy)
                        .animation(.easeInOut(duration: 11), value: ctx.date)
                }
            }
        }
        .ignoresSafeArea()
    }
}
