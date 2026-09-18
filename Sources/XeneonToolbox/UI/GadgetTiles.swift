import SwiftUI
import AppKit
import ToolboxKit

// MARK: - Up Next (calendar)

struct UpNextTile: View {
    @ObservedObject var calendar: CalendarService
    var size: TileSize = .w

    var body: some View {
        TileSurface(accent: Theme.netUp) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Up next", systemImage: "calendar", accent: Theme.netUp)
                Spacer(minLength: 10)
                let events = Array(calendar.upcoming.prefix(size.columns > 1 ? 4 : 3))
                if events.isEmpty {
                    emptyState
                } else if size.columns > 1, events.count > 2 {
                    HStack(alignment: .top, spacing: 10) {
                        column(Array(events.prefix(2)))
                        column(Array(events.dropFirst(2)))
                    }
                } else {
                    column(events)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func column(_ events: [CalendarService.Event]) -> some View {
        VStack(spacing: 8) {
            ForEach(events) { row($0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ e: CalendarService.Event) -> some View {
        let color = Color(red: e.calendarColorRGB.0, green: e.calendarColorRGB.1, blue: e.calendarColorRGB.2)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(e.timeLabel + (e.isNow ? " · now" : "")).font(.deck(13))
                    .foregroundStyle(e.isNow ? color : Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if e.isNow { Circle().fill(color).frame(width: 7, height: 7).deckGlow(color, strength: 0.8) }
        }
        .padding(.horizontal, 12).frame(height: 54).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(e.isNow ? color.opacity(0.12) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(e.isNow ? color.opacity(0.45) : Theme.stroke, lineWidth: 1))
    }

    @ViewBuilder private var emptyState: some View {
        if calendar.hasAccess {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                Text("Nothing else today").font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PermissionGuide(.calendar, compact: size.columns == 1) { calendar.refresh() }
        }
    }
}

// MARK: - Tasks

struct TasksTile: View {
    @ObservedObject var todos: TodoStore
    var size: TileSize = .s
    var onOpen: () -> Void = {}

    private var open: [TodoItem] { todos.sorted.filter { !$0.done } }
    private var overdue: Int { open.filter { $0.isOverdue }.count }
    private var today: Int { open.filter { $0.dueAt.map { Calendar.current.isDateInToday($0) && $0 >= Date() } ?? false }.count }

    var body: some View {
        TileSurface(accent: Theme.netUp) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onOpen) {
                    TileHeader(title: "Tasks", systemImage: "checklist", accent: Theme.netUp)
                        .overlay(alignment: .topTrailing) { countPill }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 10)
                let shown = Array(open.prefix(size.columns > 1 ? 5 : 3))
                if shown.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(Theme.battery)
                        Text("Nothing on your list").font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 6) { ForEach(shown) { row($0) } }
                }
                Spacer(minLength: 0)
                if open.count > (size.columns > 1 ? 5 : 3) {
                    Button(action: onOpen) {
                        Text("\(open.count - (size.columns > 1 ? 5 : 3)) more in Tasks")
                            .font(.deck(12, .semibold)).foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var countPill: some View {
        let (text, color): (String, Color) = overdue > 0 ? ("\(overdue) overdue", Theme.critical)
            : today > 0 ? ("\(today) today", Theme.warning)
            : open.isEmpty ? ("All clear", Theme.battery) : ("\(open.count) open", Theme.textSecondary)
        Text(text).font(.deck(11, .bold)).foregroundStyle(color)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(color.opacity(0.14)))
            .offset(y: -4)
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 10) {
            Button { todos.toggle(item.id) } label: {
                Image(systemName: "circle").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(item.isOverdue ? Theme.critical : Theme.textSecondary)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }.buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.deck(14, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let due = item.dueAt {
                    Text((item.isOverdue ? "Overdue · " : "") + Self.fmt(due)).font(.deck(11, .semibold))
                        .foregroundStyle(item.isOverdue ? Theme.critical : Theme.netUp)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8).frame(height: 44).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private static func fmt(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) { f.dateFormat = "h:mm a" }
        else if cal.isDateInTomorrow(d) { f.dateFormat = "'Tomorrow' h:mm a" }
        else { f.dateFormat = "EEE d MMM" }
        return f.string(from: d)
    }
}

// MARK: - Thermals

struct ThermalsTile: View {
    var thermals: ThermalSnapshot?

    private var soc: Double? { thermals?.socC }
    private var tint: Color {
        guard let t = soc else { return Theme.heat }
        return t >= 95 ? Theme.critical : t >= 85 ? Theme.warning : Theme.heat
    }

    var body: some View {
        TileSurface(accent: tint) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Thermals", systemImage: "thermometer.medium", accent: tint)
                Spacer(minLength: 8)
                if let t = thermals, let s = t.socC {
                    RingGauge(value: min(1, s / 110), color: tint) {
                        VStack(spacing: 2) {
                            Text("\(Int(s.rounded()))°").font(.readout(46, .bold)).foregroundStyle(Theme.textPrimary)
                            Text("soc").font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer(minLength: 8)
                    HStack {
                        if let g = t.gpuC {
                            Label("GPU \(Int(g.rounded()))°", systemImage: "cube.transparent.fill")
                                .font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if let rpm = t.fanRPM.max() {
                            Label("\(Int(rpm.rounded())) rpm", systemImage: "fanblades")
                                .font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("fanless").font(.deck(13)).foregroundStyle(Theme.textFaint)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "thermometer.medium.slash").font(.system(size: 32)).foregroundStyle(Theme.textFaint)
                        Text(thermals == nil ? "Reading sensors…" : "No sensors on this Mac")
                            .font(.deck(14)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Running apps (dock)

struct DockTile: View {
    @ObservedObject var monitor: RunningAppsMonitor
    var size: TileSize = .w

    private var perRow: Int { size.columns > 1 ? 7 : 3 }
    private var capacity: Int { perRow * 2 }

    var body: some View {
        TileSurface(accent: Theme.accent) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Running", systemImage: "macwindow.on.rectangle", accent: Theme.accent)
                    .overlay(alignment: .topTrailing) {
                        Text("\(monitor.apps.count)").font(.readout(12, .bold)).foregroundStyle(Theme.textFaint).offset(y: -2)
                    }
                Spacer(minLength: 12)
                let shown = Array(monitor.apps.prefix(capacity))
                if shown.isEmpty {
                    Text("No apps running").font(.deck(14)).foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<((shown.count + perRow - 1) / perRow), id: \.self) { r in
                            HStack(spacing: 12) {
                                ForEach(shown[(r * perRow)..<min(shown.count, (r + 1) * perRow)]) { app in appButton(app) }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if monitor.apps.count > capacity {
                    Text("+\(monitor.apps.count - capacity) more").font(.deck(12)).foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    private func appButton(_ app: RunningAppsMonitor.App) -> some View {
        Button { monitor.activate(app) } label: {
            VStack(spacing: 5) {
                Image(nsImage: RunningAppsMonitor.icon(for: app)).resizable().interpolation(.high)
                    .frame(width: 52, height: 52)
                Circle().fill(app.isActive ? Theme.accent : .clear).frame(width: 5, height: 5)
            }
            .frame(width: 60, height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(app.name)
        // Window-space frame so a driver long-press can be matched to this app.
        .background(GeometryReader { p in
            Color.clear.preference(key: DockIconFrameKey.self, value: [app.path: p.frame(in: .global)])
        })
    }
}

/// Running-app icon frames in window coordinates, for the long-press picker.
struct DockIconFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Clipboard

struct ClipboardTile: View {
    @ObservedObject var store: ClipboardStore
    var size: TileSize = .s
    @State private var copied: String?

    var body: some View {
        TileSurface(accent: Theme.disk) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Clipboard", systemImage: "doc.on.clipboard", accent: Theme.disk)
                    .overlay(alignment: .topTrailing) { pauseButton }
                Spacer(minLength: 10)
                let limit = size.columns > 1 ? 8 : 4
                let items = Array(store.history.items.prefix(limit))
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                        Text(store.paused ? "Paused" : "Copy something and it shows up here")
                            .font(.deck(14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if size.columns > 1, items.count > 4 {
                    HStack(alignment: .top, spacing: 10) {
                        column(Array(items.prefix(4).enumerated()))
                        column(Array(items.enumerated().dropFirst(4)))
                    }
                } else {
                    column(Array(items.enumerated()))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func column(_ items: [(offset: Int, element: String)]) -> some View {
        VStack(spacing: 6) {
            ForEach(items, id: \.offset) { i, text in row(i, text) }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ index: Int, _ text: String) -> some View {
        HStack(spacing: 6) {
            Button {
                store.copyBack(text)
                copied = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == text { copied = nil } }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: copied == text ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(copied == text ? Theme.battery : Theme.textFaint).frame(width: 16)
                    Text(Self.firstLine(text)).font(.deck(14, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).frame(height: 44).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.05)))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }.buttonStyle(.pressable)
            Button { store.remove(at: index) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textFaint)
                    .frame(width: 34, height: 44).contentShape(Rectangle())
            }.buttonStyle(.pressable)
        }
    }

    private var pauseButton: some View {
        Button { store.paused.toggle() } label: {
            Image(systemName: store.paused ? "play.fill" : "pause.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(store.paused ? Theme.warning : Theme.textFaint)
                .frame(width: 34, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .offset(y: -6)
        .help(store.paused ? "Resume watching the clipboard" : "Pause watching the clipboard")
    }

    private static func firstLine(_ s: String) -> String {
        let line = s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? s
        return line.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Now Playing

struct NowPlayingTile: View {
    @ObservedObject var media: MediaController
    var size: TileSize = .s
    var onExpand: () -> Void = {}

    var body: some View {
        TileSurface(accent: Theme.memory) {
            if media.available, let np = media.nowPlaying {
                if size.columns > 1 { wide(np) } else { small(np) }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TileHeader(title: "Now playing", systemImage: "music.note", accent: Theme.memory)
                    Spacer(minLength: 12)
                    emptyState
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // The artwork is the tile: it bleeds to the top edge under the header, the
    // song sits on its lower gradient, and the transport rests beneath.
    private func small(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                artBleed(np, corner: Theme.tileCorner)
                TileHeader(title: "Now playing", systemImage: "music.note", accent: Theme.memory) {
                    sourceLamp(np)
                }
                .padding(20)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(np.artist.isEmpty ? np.album : np.artist).font(.deck(13, .medium))
                        .foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                .padding(.horizontal, 20).padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
            }
            .frame(height: 196)
            .frame(maxWidth: .infinity)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.tileCorner, bottomLeadingRadius: 0,
                                              bottomTrailingRadius: 0, topTrailingRadius: Theme.tileCorner, style: .continuous))
            .padding(.horizontal, -20).padding(.top, -20)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            Spacer(minLength: 10)
            ScrubBar(np: np, compact: true) { media.seek(to: $0) }
            Spacer(minLength: 10)
            transport(np, compact: true).frame(maxWidth: .infinity)
        }
    }

    private func wide(_ np: NowPlaying) -> some View {
        HStack(spacing: 0) {
            artBleed(np, corner: Theme.tileCorner)
            .frame(width: 300)
            .frame(maxHeight: .infinity)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.tileCorner, bottomLeadingRadius: Theme.tileCorner,
                                              bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
            .padding(.leading, -20).padding(.vertical, -20)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Now playing", systemImage: "music.note", accent: Theme.memory) { sourceLamp(np) }
                Spacer(minLength: 8)
                Text(np.title).font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text(np.artist.isEmpty ? np.album : np.artist).font(.deck(15, .medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    .padding(.top, 4)
                Spacer(minLength: 12)
                ScrubBar(np: np, compact: false) { media.seek(to: $0) }
                Spacer(minLength: 14)
                transport(np, compact: false)
            }
            .padding(.leading, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Full-bleed artwork with a gradient into the tile at the bottom (and the
    /// left edge on wide), so text and header read over it. No artwork: a soft
    /// rose wash with the note.
    private func artBleed(_ np: NowPlaying, corner: CGFloat) -> some View {
        // Color.clear takes the proposed size; the image fills it and is clipped,
        // so the artwork never pushes the tile's layout around.
        Color.clear
            .overlay {
                if let art = np.artwork {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.memory.opacity(0.35), Theme.tileBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.system(size: 54, weight: .medium)).foregroundStyle(Theme.memory.opacity(0.7))
                    }
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: Theme.tileBottom.opacity(0.92), location: 0),
                                       .init(color: .clear, location: 0.4),
                                       .init(color: .clear, location: 0.5),
                                       .init(color: Theme.tileBottom.opacity(0.94), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                if size.columns > 1 {
                    LinearGradient(colors: [.clear, Theme.tileBottom], startPoint: .init(x: 0.6, y: 0.5), endPoint: .trailing)
                }
            }
            .clipped()
    }

    private func sourceLamp(_ np: NowPlaying) -> some View {
        HStack(spacing: 6) {
            Lamp(color: np.isPlaying ? Theme.battery : Theme.textFaint, on: np.isPlaying, size: 6)
            Text(np.source == .spotify ? "Spotify" : "Music").font(.deck(12, .medium)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func transport(_ np: NowPlaying, compact: Bool) -> some View {
        HStack(spacing: compact ? 14 : 16) {
            circle("backward.fill", size: compact ? 14 : 16, diameter: compact ? 42 : 46) { media.previous() }
            circle(np.isPlaying ? "pause.fill" : "play.fill", size: compact ? 18 : 20, diameter: compact ? 54 : 58, filled: true) { media.togglePlayPause() }
            circle("forward.fill", size: compact ? 14 : 16, diameter: compact ? 42 : 46) { media.next() }
        }
    }

    private func circle(_ icon: String, size: CGFloat, diameter: CGFloat, filled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(filled ? Theme.backgroundEdge : Theme.textPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.08))))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(filled ? 0.3 : 0.12), Theme.bezelDark],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
            Text("Nothing playing").font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                openButton("Music", bundle: "com.apple.Music")
                openButton("Spotify", bundle: "com.spotify.client")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func openButton(_ name: String, bundle: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            GhostButton(title: name, tint: Theme.textPrimary, height: 38) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
    }
}
