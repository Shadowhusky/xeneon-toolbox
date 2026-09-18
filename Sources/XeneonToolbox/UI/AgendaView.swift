import SwiftUI
import AppKit

/// Today's schedule as a console: what's next on the left, the day drawn along
/// the strip in the middle, every event listed on the right.
struct AgendaView: View {
    let events: [CalendarService.Event]
    var onClose: () -> Void

    private var timed: [CalendarService.Event] { events.filter { !$0.allDay } }
    private var allDay: [CalendarService.Event] { events.filter(\.allDay) }

    private var subtitle: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"
        let left = timed.filter { !$0.isPast }.count
        let tail = events.isEmpty ? "nothing scheduled" : left == 0 ? "done for the day" : left == 1 ? "1 event to go" : "\(left) events to go"
        return "\(f.string(from: Date())), \(tail)"
    }

    var body: some View {
        ModalScaffold(dim: 0.62, onDismiss: onClose) {
            DetailShell(title: "Today", icon: "calendar", tint: Theme.netUp, subtitle: subtitle, actions: actions, onClose: onClose) {
                if events.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.textFaint)
                        Text("Nothing scheduled today").font(.deck(16, .medium)).foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        upNext.frame(width: 440).frame(maxHeight: .infinity)
                        ConsolePanel(title: "The day", trailing: allDay.isEmpty ? nil : allDay.map(\.title).joined(separator: ", ")) {
                            DayTimeline(events: timed)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ConsolePanel(title: "Schedule", trailing: "\(events.count) in all") {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 8) { ForEach(events) { row($0) } }
                            }
                        }
                        .frame(width: 600).frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
    }

    private var actions: [DetailAction] {
        [DetailAction(title: "Open Calendar", icon: "arrow.up.forward.app", tint: Theme.textSecondary) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"), configuration: .init())
        }]
    }

    // MARK: Up next

    @ViewBuilder private var upNext: some View {
        let current = timed.first(where: \.isNow), following = timed.first { !$0.isPast && !$0.isNow }
        VStack(alignment: .leading, spacing: 14) {
            if let e = current ?? following {
                let color = Self.color(e)
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.isNow ? "Happening now" : "Up next").font(.deckLabel).foregroundStyle(color)
                    Text(e.title).font(.deck(30, .semibold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                    Text(Self.relative(e)).font(.hero(54)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    Text(Self.span(e)).font(.readout(15, .semibold)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if current != nil, let then = following {
                    ConsolePanel(title: "Then") {
                        FactRow(icon: "arrow.turn.down.right", label: then.title, value: then.timeLabel, tint: Self.color(then))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All clear").font(.deck(30, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Nothing else on the calendar today.").font(.deck(15)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            ConsolePanel(title: "Today in numbers") {
                HStack(spacing: 10) {
                    MiniStat(value: "\(timed.count)", caption: timed.count == 1 ? "event" : "events")
                    MiniStat(value: Self.hours(timed.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }), caption: "booked")
                    MiniStat(value: Self.freeUntil(timed), caption: "free until", tint: Theme.battery)
                }
            }
        }
    }

    private func row(_ e: CalendarService.Event) -> some View {
        let color = Self.color(e)
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.deck(16, .semibold))
                    .foregroundStyle(e.isPast ? Theme.textFaint : Theme.textPrimary)
                    .strikethrough(e.isPast, color: Theme.textFaint)
                    .lineLimit(1)
                Text(e.allDay ? "All day" : Self.span(e) + (e.isNow ? ", now" : ""))
                    .font(.deck(13)).foregroundStyle(e.isNow ? color : Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if e.isNow { Lamp(color: color, on: true, size: 8) }
        }
        .padding(.horizontal, 14).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(e.isNow ? color.opacity(0.14) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(e.isNow ? color.opacity(0.5) : Theme.stroke, lineWidth: 1))
    }

    // MARK: Formatting

    fileprivate static func color(_ e: CalendarService.Event) -> Color {
        Color(red: e.calendarColorRGB.0, green: e.calendarColorRGB.1, blue: e.calendarColorRGB.2)
    }

    private static func span(_ e: CalendarService.Event) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return "\(f.string(from: e.start)) to \(f.string(from: e.end))"
    }

    private static func relative(_ e: CalendarService.Event) -> String {
        let seconds = (e.isNow ? e.end : e.start).timeIntervalSinceNow
        let minutes = max(0, Int((seconds / 60).rounded()))
        let amount = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        return e.isNow ? "\(amount) left" : "in \(amount)"
    }

    private static func hours(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%.1f h", Double(minutes) / 60)
    }

    private static func freeUntil(_ timed: [CalendarService.Event]) -> String {
        if timed.contains(where: \.isNow) { return "busy" }
        guard let next = timed.first(where: { !$0.isPast }) else { return "tonight" }
        return next.timeLabel
    }
}

/// The day along the strip: hours across, events as blocks in as many lanes
/// as they need, and a line for now.
private struct DayTimeline: View {
    let events: [CalendarService.Event]

    private var window: (start: Date, hours: Int) {
        let cal = Calendar.current, now = Date()
        let first = min(events.map(\.start).min() ?? now, now), last = max(events.map(\.end).max() ?? now, now)
        let startHour = max(0, cal.component(.hour, from: first) - 1)
        let endHour = min(24, cal.component(.hour, from: last) + 2)
        let start = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: now) ?? now
        return (start, max(6, endHour - startHour))
    }

    private static let labelWidth: CGFloat = 190

    /// Lanes are packed by what each event occupies on screen: a short event
    /// still needs room for its label, which runs past the block.
    private func lanes(x: (Date) -> CGFloat) -> [[CalendarService.Event]] {
        var lanes: [[CalendarService.Event]] = [], edges: [CGFloat] = []
        for e in events.sorted(by: { $0.start < $1.start }) {
            let x0 = x(e.start), x1 = max(x(e.end), x0 + Self.labelWidth)
            if let i = edges.firstIndex(where: { $0 <= x0 }) { lanes[i].append(e); edges[i] = x1 }
            else { lanes.append([e]); edges.append(x1) }
        }
        return lanes
    }

    var body: some View {
        GeometryReader { geo in
            let w = window, span = Double(w.hours) * 3600
            let x = { (d: Date) -> CGFloat in CGFloat(max(0, min(1, d.timeIntervalSince(w.start) / span))) * geo.size.width }
            let top: CGFloat = 8, bottom = geo.size.height - 30
            let lanes = lanes(x: x), gaps = CGFloat(max(0, lanes.count - 1)) * 10
            let laneHeight = min(132, (bottom - top - 16 - gaps) / CGFloat(max(1, lanes.count)))
            let firstLane = top + (bottom - top - laneHeight * CGFloat(lanes.count) - gaps) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0...w.hours, id: \.self) { h in
                    let px = CGFloat(h) / CGFloat(w.hours) * geo.size.width
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: bottom - top).offset(x: px, y: top)
                    if h < w.hours, h % (w.hours > 12 ? 2 : 1) == 0 {
                        Text(Self.hourLabel(w.start.addingTimeInterval(Double(h) * 3600))).font(.deck(12, .medium))
                            .foregroundStyle(Theme.textFaint).offset(x: px + 6, y: geo.size.height - 18)
                    }
                }
                Rectangle().fill(Theme.accent).frame(width: 2, height: bottom - top + 6).offset(x: x(Date()) - 1, y: top - 3)
                ForEach(Array(lanes.enumerated()), id: \.offset) { lane, row in
                    ForEach(row) { e in
                        let x0 = x(e.start), width = max(10, x(e.end) - x0 - 4), color = AgendaView.color(e)
                        let y = firstLane + CGFloat(lane) * (laneHeight + 10)
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(e.isPast ? 0.07 : e.isNow ? 0.26 : 0.16))
                            .overlay(alignment: .leading) { Rectangle().fill(color.opacity(e.isPast ? 0.4 : 1)).frame(width: 4) }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(width: width, height: laneHeight).offset(x: x0, y: y)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.title).font(.deck(15, .semibold)).foregroundStyle(e.isPast ? Theme.textFaint : Theme.textPrimary).lineLimit(2)
                            Text(e.timeLabel).font(.readout(12, .medium)).foregroundStyle(e.isNow ? color : Theme.textSecondary)
                        }
                        .frame(width: max(width, Self.labelWidth) - 24, alignment: .leading)
                        .offset(x: x0 + 14, y: y + 10)
                    }
                }
                let nowX = x(Date())
                Text("Now").font(.deck(12, .semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Theme.background))
                    .offset(x: min(nowX + 6, geo.size.width - 46), y: geo.size.height - 19)
            }
        }
    }

    private static func hourLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: date).lowercased().replacingOccurrences(of: " ", with: "")
    }
}
