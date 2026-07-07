import SwiftUI

/// Today's schedule — a modal agenda reachable from the ambient screen's next
/// event. Timeline of the day's events with per-calendar colours; the current
/// event is highlighted, past ones dimmed.
struct AgendaView: View {
    let events: [CalendarService.Event]
    var onClose: () -> Void

    private var dateLine: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f.string(from: Date())
    }

    var body: some View {
        ModalScaffold(dim: 0.62, onDismiss: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today").font(.deck(24, .bold)).foregroundStyle(Theme.textPrimary)
                        Text(dateLine).font(.deck(14)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))).contentShape(Circle())
                    }.buttonStyle(.pressable)
                }
                .padding(.bottom, 14)

                if events.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.textFaint)
                        Text("Nothing scheduled today").font(.deck(16, .medium)).foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(events) { row($0) }
                        }
                    }
                }
            }
            .padding(24).frame(width: 720, height: 560)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        }
    }

    private func row(_ e: CalendarService.Event) -> some View {
        let color = Color(red: e.calendarColorRGB.0, green: e.calendarColorRGB.1, blue: e.calendarColorRGB.2)
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.deck(16, .semibold))
                    .foregroundStyle(e.isPast ? Theme.textFaint : Theme.textPrimary)
                    .strikethrough(e.isPast, color: Theme.textFaint)
                    .lineLimit(1)
                if !e.allDay {
                    Text(e.timeLabel + (e.isNow ? " · now" : ""))
                        .font(.deck(13)).foregroundStyle(e.isNow ? color : Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if e.isNow {
                Circle().fill(color).frame(width: 8, height: 8).deckGlow(color, strength: 0.8)
            }
        }
        .padding(.horizontal, 14).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(e.isNow ? color.opacity(0.14) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(e.isNow ? color.opacity(0.5) : Theme.stroke, lineWidth: 1))
    }
}
