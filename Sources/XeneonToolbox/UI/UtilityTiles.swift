import SwiftUI
import ToolboxKit

// MARK: - Focus

struct FocusTile: View {
    @ObservedObject var timer: FocusTimer
    var onOpen: () -> Void = {}

    var body: some View {
        TileSurface(accent: Theme.accent) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Focus", systemImage: "timer", accent: Theme.accent) {
                    HStack(spacing: 6) {
                        Lamp(color: Theme.accent, on: timer.running, size: 6)
                        Text(timer.running ? "running" : "\(timer.state.total / 60) min")
                            .font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                    }
                }
                Spacer(minLength: 8)
                RingGauge(value: timer.fraction, color: Theme.accent) {
                    Text(timer.clock).font(.readout(30, .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                Spacer(minLength: 10)
                HStack(spacing: 8) {
                    PrimaryButton(title: timer.running ? "Pause" : "Start",
                                  icon: timer.running ? "pause.fill" : "play.fill", height: 44) { timer.toggle() }
                        .frame(maxWidth: .infinity)
                    GhostButton(title: "Reset", tint: Theme.textSecondary, height: 44) { timer.reset() }
                }
            }
        }
    }
}

// MARK: - World clocks

struct WorldClocksTile: View {
    @ObservedObject var store: WorldClockStore
    var size: TileSize = .w

    var body: some View {
        TileSurface(accent: Theme.ice) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "World clocks", systemImage: "globe", accent: Theme.ice) {
                    if !store.clocks.isEmpty {
                        Text("\(store.clocks.count) \(store.clocks.count == 1 ? "city" : "cities")")
                            .font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                    }
                }
                Spacer(minLength: 10)
                if store.clocks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "globe").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                        Text("Add cities in Clock").font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TimelineView(.everyMinute) { ctx in
                        if size.columns > 1 {
                            let clocks = Array(store.clocks.prefix(6))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(clocks) { cell($0, at: ctx.date) }
                            }
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(store.clocks.prefix(3))) { row($0, at: ctx.date) }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cell(_ clock: WorldClock, at now: Date) -> some View {
        let tz = clock.timeZone ?? .current
        let day = WorldClockInfo.isDaytime(in: tz, at: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: day ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(day ? Theme.accent : Theme.gpu)
                Text(clock.name).font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .environment(\.timeZone, tz)
                .font(.readout(28, .medium)).foregroundStyle(Theme.textPrimary)
            Text(WorldClockInfo.offsetLabel(of: tz, at: now) + (WorldClockInfo.dayLabel(of: tz, at: now).map { " · \($0)" } ?? ""))
                .font(.deck(11, .medium)).foregroundStyle(Theme.textFaint).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(Theme.wellFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
    }

    private func row(_ clock: WorldClock, at now: Date) -> some View {
        let tz = clock.timeZone ?? .current
        let day = WorldClockInfo.isDaytime(in: tz, at: now)
        return HStack(spacing: 10) {
            Image(systemName: day ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(day ? Theme.accent : Theme.gpu)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(clock.name).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(WorldClockInfo.offsetLabel(of: tz, at: now)).font(.deck(11, .medium)).foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 6)
            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .environment(\.timeZone, tz)
                .font(.readout(22, .medium)).foregroundStyle(Theme.textPrimary)
        }
        .frame(height: 48)
    }
}

// MARK: - Weather

struct WeatherTile: View {
    var weather: Weather?
    var loading = false
    var size: TileSize = .w

    var body: some View {
        TileSurface(accent: Theme.ice) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Weather", systemImage: "cloud.sun.fill", accent: Theme.ice) {
                    if let w = weather, !w.city.isEmpty {
                        Text(w.city).font(.deck(12, .medium)).foregroundStyle(Theme.textFaint).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Group {
                    if let w = weather {
                        if size.columns > 1 { wide(w) } else { small(w) }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: loading ? "cloud" : "location.slash").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                            Text(loading ? "Loading forecast…" : "Weather unavailable").font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        // One quiet cross-fade when the forecast arrives or refreshes.
        .animation(Motion.smooth, value: weather)
    }

    private func now(_ w: Weather, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: w.symbol).font(.system(size: big ? 34 : 26, weight: .medium))
                    .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice)
                Text(w.displayTemp).font(.hero(big ? 64 : 48)).foregroundStyle(Theme.textPrimary)
            }
            Text(w.condition).font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                if let hi = w.displayHigh, let lo = w.displayLow {
                    Text("H \(hi)  L \(lo)").font(.readout(12, .semibold)).foregroundStyle(Theme.textFaint)
                }
                if let wind = w.displayWind {
                    Label(wind, systemImage: "wind").font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    private func wide(_ w: Weather) -> some View {
        HStack(alignment: .center, spacing: 16) {
            now(w, big: true).frame(width: 190, alignment: .leading)
            Well {
                HStack(spacing: 0) {
                    ForEach(Array(w.hours.prefix(6))) { h in
                        VStack(spacing: 6) {
                            Text(h.hourLabel).font(.deck(11, .medium)).foregroundStyle(Theme.textFaint)
                            Image(systemName: h.symbol).font(.system(size: 18, weight: .medium))
                                .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice)
                                .frame(height: 22)
                            Text(h.temp()).font(.readout(15, .semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if w.hours.isEmpty {
                        Text("Hourly forecast unavailable").font(.deck(13)).foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func small(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            now(w, big: false)
            HStack(spacing: 6) {
                ForEach(Array(w.days.prefix(3))) { d in
                    VStack(spacing: 3) {
                        Text(d.weekday).font(.deck(11, .medium)).foregroundStyle(Theme.textFaint)
                        Image(systemName: d.symbol).font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.multicolor).foregroundStyle(Theme.ice).frame(height: 18)
                        Text(d.high()).font(.readout(13, .semibold)).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(Theme.wellFill))
                }
            }
        }
    }
}

// MARK: - Devices

struct DevicesTile: View {
    @ObservedObject var devices: BluetoothDevices
    var size: TileSize = .s

    var body: some View {
        let list = devices.connected
        TileSurface(accent: Theme.disk) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Devices", systemImage: "wave.3.right", accent: Theme.disk) {
                    if !list.isEmpty {
                        Text("\(list.count) connected").font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                    }
                }
                Spacer(minLength: 10)
                if list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: devices.loaded ? "wave.3.right.circle" : "wave.3.right")
                            .font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                        Text(devices.loaded ? "Nothing connected" : "Looking for devices…")
                            .font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if size.columns > 1 {
                    HStack(alignment: .top, spacing: 10) {
                        column(Array(list.prefix(3)))
                        column(Array(list.dropFirst(3).prefix(3)))
                    }
                } else {
                    column(Array(list.prefix(3)))
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { devices.start() }
        .onDisappear { devices.stop() }
    }

    private func column(_ items: [BluetoothPeripheral]) -> some View {
        VStack(spacing: 6) {
            ForEach(items) { row($0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ d: BluetoothPeripheral) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(d.kind)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.disk)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(Theme.disk.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(detail(d)).font(.deck(11, .medium)).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let level = d.lowest {
                Text("\(level)%").font(.readout(16, .semibold)).foregroundStyle(Self.tint(level))
            }
        }
        .frame(height: 48)
    }

    private func detail(_ d: BluetoothPeripheral) -> String {
        var parts: [String] = []
        if let l = d.left, let r = d.right { parts.append("L \(l)%  R \(r)%") }
        if let c = d.caseLevel { parts.append("Case \(c)%") }
        return parts.isEmpty ? (d.hasBattery ? "Connected" : "Connected · no battery info") : parts.joined(separator: " · ")
    }

    private static func tint(_ level: Int) -> Color {
        level <= 15 ? Theme.critical : level <= 30 ? Theme.warning : Theme.battery
    }

    private static func symbol(_ kind: BluetoothPeripheral.Kind) -> String {
        switch kind {
        case .headphones: return "headphones"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "hand.point.up.left.fill"
        case .gamepad: return "gamecontroller.fill"
        case .speaker: return "hifispeaker.fill"
        case .phone: return "iphone"
        case .watch: return "applewatch"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Quick actions

struct QuickActionsTile: View {
    let model: ToolboxModel
    @ObservedObject var keepAwake: KeepAwake
    var size: TileSize = .w

    private static let wide: [DeckSystemAction] = [.keepAwake, .darkMode, .screenshot, .lockScreen, .sleepDisplay, .missionControl]
    private static let small: [DeckSystemAction] = [.keepAwake, .darkMode, .screenshot, .lockScreen]

    var body: some View {
        TileSurface(accent: Theme.netUp) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(title: "Quick actions", systemImage: "bolt.fill", accent: Theme.netUp) {
                    if keepAwake.on {
                        HStack(spacing: 6) {
                            Lamp(color: Theme.accent, on: true, size: 6)
                            Text("Mac stays awake").font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
                        }
                    }
                }
                Spacer(minLength: 12)
                let actions = size.columns > 1 ? Self.wide : Self.small
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: size.columns > 1 ? 3 : 2), spacing: 8) {
                    ForEach(actions, id: \.self) { key($0) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func key(_ action: DeckSystemAction) -> some View {
        let lit = action == .keepAwake && keepAwake.on
        return Button { model.runDeck(.system(action)) } label: {
            VStack(spacing: 8) {
                Image(systemName: action.symbol).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(lit ? Theme.accent : Theme.textPrimary)
                Text(Self.label(action)).font(.deck(12, .semibold))
                    .foregroundStyle(lit ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous)
                    .fill(lit
                          ? LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            )
            .bezel(corner: Theme.wellCorner, tint: lit ? Theme.accent : .clear)
            .contentShape(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private static func label(_ a: DeckSystemAction) -> String {
        switch a {
        case .keepAwake: return "Keep awake"
        case .darkMode: return "Dark mode"
        case .screenshot: return "Screenshot"
        case .lockScreen: return "Lock screen"
        case .sleepDisplay: return "Sleep display"
        case .missionControl: return "Mission Control"
        default: return a.label
        }
    }
}
