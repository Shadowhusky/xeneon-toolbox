import SwiftUI
import ToolboxKit

/// Minimal mode — mostly-black, just the time, a few vitals, and the next
/// reminder (OLED/battery friendly). Tap anywhere to return to full.
struct MinimalView: View {
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var todos: TodoStore

    /// Soonest-due open reminder (overdue ones sort first, being earliest).
    private var nextReminder: TodoItem? {
        todos.items.filter { !$0.done && $0.dueAt != nil }
            .min { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }
    private var openCount: Int { todos.items.filter { !$0.done }.count }

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 26) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 6) {
                        Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 140, weight: .bold, design: .rounded)).monospacedDigit()
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
                taskLine
            }
            VStack {
                Spacer()
                Text("Tap anywhere to exit").font(.deck(13)).foregroundStyle(.white.opacity(0.22)).padding(.bottom, 26)
            }
        }
    }

    @ViewBuilder private var taskLine: some View {
        if let r = nextReminder, let due = r.dueAt {
            let overdue = r.isOverdue
            HStack(spacing: 9) {
                Image(systemName: overdue ? "exclamationmark.circle.fill" : "bell.fill").font(.system(size: 15))
                Text("\(r.title) · \(Self.time(due))").font(.deck(18, .medium)).lineLimit(1)
            }
            .foregroundStyle((overdue ? Theme.batteryLow : Color.white).opacity(overdue ? 0.75 : 0.45))
        } else if openCount > 0 {
            HStack(spacing: 9) {
                Image(systemName: "checklist").font(.system(size: 15))
                Text("\(openCount) task\(openCount == 1 ? "" : "s")").font(.deck(18, .medium))
            }
            .foregroundStyle(.white.opacity(0.34))
        }
    }

    private func stat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(color.opacity(0.85))
            Text(value).font(.readout(28, .semibold)).foregroundStyle(.white.opacity(0.7))
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
