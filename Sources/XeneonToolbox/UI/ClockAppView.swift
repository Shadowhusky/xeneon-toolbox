import SwiftUI
import ToolboxKit

struct ClockAppView: View {
    @ObservedObject var store: WorldClockStore
    var exportMode = false

    var body: some View {
        HStack(spacing: Theme.tileGap) {
            NowCard()
            WorldClocksCard(store: store, exportMode: exportMode).frame(maxWidth: 470)
            FocusTimerCard().frame(maxWidth: 470)
        }
    }
}

// MARK: - Now

private struct NowCard: View {
    var body: some View {
        TileSurface(accent: Theme.accent) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let now = ctx.date
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(title: "Now", systemImage: "clock.fill", accent: Theme.accent)
                    Spacer()
                    Text(now, format: .dateTime.weekday(.wide))
                        .font(.deck(30, .semibold)).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.readout(116, .bold)).foregroundStyle(Theme.textPrimary)
                        Text(now, format: .dateTime.second(.twoDigits))
                            .font(.readout(40, .bold)).foregroundStyle(Theme.accent)
                            .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                    }
                    .lineLimit(1).minimumScaleFactor(0.5)
                    Text(now, format: .dateTime.month(.wide).day().year())
                        .font(.deck(20, .medium)).foregroundStyle(Theme.textFaint)
                    Spacer()
                    DayProgressBar(date: now)
                }
            }
        }
    }
}

/// The page's signature element: a full-day gradient (deep night → dawn → midday
/// → dusk → night) with a glowing marker at the current moment — you read where
/// you are in the day at a glance.
private struct DayProgressBar: View {
    let date: Date
    private static let band = [
        Color(red: 0.10, green: 0.11, blue: 0.28),   // night
        Color(red: 0.98, green: 0.62, blue: 0.40),   // dawn
        Color(red: 0.55, green: 0.86, blue: 0.96),   // midday
        Color(red: 0.98, green: 0.55, blue: 0.45),   // dusk
        Color(red: 0.10, green: 0.11, blue: 0.28),   // night
    ]
    private var fraction: Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let secs = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        return Double(secs) / 86_400
    }
    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: Self.band, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                        .shadow(color: Theme.accent.opacity(0.9), radius: 7)
                        .offset(x: max(0, min(w - 16, w * fraction - 8)))
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack(spacing: 0) {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { t in
                    Text(t).font(.deck(11, .semibold)).foregroundStyle(Theme.textFaint)
                    if t != "24" { Spacer() }
                }
            }
        }
    }
}

// MARK: - World

private struct WorldClocksCard: View {
    @ObservedObject var store: WorldClockStore
    var exportMode = false
    @State private var editing = false
    @State private var adding = false
    @State private var query = ""

    var body: some View {
        TileSurface(accent: Theme.memory) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 14)
                if adding {
                    picker
                } else {
                    clockList
                    if editing {
                        Spacer(minLength: 12)
                        addButton
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.memory)
                Text("WORLD").font(.deck(13, .bold)).tracking(1.8).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if !exportMode {
                    if adding {
                        headerButton("Done", "checkmark") { adding = false; query = "" }
                    } else {
                        headerButton(editing ? "Done" : "Edit", editing ? "checkmark" : "slider.horizontal.3") {
                            editing.toggle()
                        }
                    }
                }
            }
            Rectangle()
                .fill(LinearGradient(colors: [Theme.memory.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
        }
    }

    private func headerButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.deck(12, .bold)).foregroundStyle(Theme.memory)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(Theme.memory.opacity(0.14)))
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var clockList: some View {
        if store.clocks.isEmpty {
            emptyState
        } else {
            let rows = VStack(spacing: 0) {
                ForEach(store.clocks) { c in
                    WorldRow(clock: c, editing: editing) { store.remove(c.id) }
                    if c.id != store.clocks.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
            if exportMode {
                rows
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) { rows }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe").font(.system(size: 36)).foregroundStyle(Theme.textFaint)
            Text("No cities yet").font(.deck(17, .semibold)).foregroundStyle(Theme.textSecondary)
            Text(editing ? "Tap Add city below." : "Tap Edit to add one.")
                .font(.deck(13)).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addButton: some View {
        Button { adding = true } label: {
            Label("Add city", systemImage: "plus")
                .font(.deck(15, .semibold)).foregroundStyle(Theme.memory)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.memory.opacity(0.13)))
        }
        .buttonStyle(.pressable)
    }

    private var picker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textFaint)
                TextField("Search cities", text: $query)
                    .textFieldStyle(.plain).font(.deck(15)).foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    let results = WorldCityCatalog.search(query)
                    ForEach(results) { city in
                        Button {
                            store.add(city); adding = false; editing = false; query = ""
                        } label: {
                            HStack {
                                Text(city.name).font(.deck(16, .medium)).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(city.timeZoneID.split(separator: "/").last.map(String.init)?
                                    .replacingOccurrences(of: "_", with: " ") ?? city.timeZoneID)
                                    .font(.deck(12)).foregroundStyle(Theme.textFaint)
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        if city.id != results.last?.id { Divider().overlay(Theme.stroke) }
                    }
                }
            }
        }
    }
}

/// One world-clock row: a day/night badge, the city with its offset and relative
/// day, and the local time. Carries its own TimelineView so the surrounding
/// scroll view never resets position on the per-second tick.
private struct WorldRow: View {
    let clock: WorldClock
    var editing: Bool
    var onRemove: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            let tz = clock.timeZone ?? .current
            let day = WorldClockInfo.isDaytime(in: tz, at: now)
            let cue = day ? Theme.netUp : Theme.memory
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(cue.opacity(0.16)).frame(width: 38, height: 38)
                    Image(systemName: day ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(cue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(clock.name).font(.deck(18, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(WorldClockInfo.offsetLabel(of: tz, at: now))
                            .font(.deck(12, .semibold)).foregroundStyle(Theme.textFaint)
                        if let dl = WorldClockInfo.dayLabel(of: tz, at: now) {
                            Text("· \(dl)").font(.deck(12, .medium)).foregroundStyle(cue.opacity(0.95))
                        }
                    }
                }
                Spacer(minLength: 8)
                if editing {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.batteryLow)
                    }
                    .buttonStyle(.pressable)
                } else {
                    Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .environment(\.timeZone, tz)
                        .font(.readout(27, .bold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Focus

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
                RingGauge(value: total == 0 ? 0 : Double(total - remaining) / Double(total), color: Theme.netUp) {
                    Text(clock).font(.readout(40, .bold)).foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 188, height: 188)
                .frame(maxWidth: .infinity)
                Spacer()
                HStack(spacing: 8) {
                    ForEach([15, 25, 45], id: \.self) { preset($0) }
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
            Text("\(mins)m").font(.deck(17, .semibold))
                .foregroundStyle(selected ? Theme.netUp : Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .font(.deck(17, .semibold))
                .foregroundStyle(accent ? Theme.netUp : Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 58)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent ? Theme.netUp.opacity(0.16) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}
