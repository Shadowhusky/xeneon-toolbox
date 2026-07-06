import SwiftUI

/// A macOS-Control-Centre-style panel: brightness, volume, and quick toggles —
/// pulled down from the top-right edge. All controls are sized for fingers.
struct ControlCenterView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var toggles: SystemToggles
    @ObservedObject var audio: AudioOutput
    @State private var brightness: Double = 90
    @State private var volume: Double = 50
    @State private var volumeAvailable = false
    private enum Picker { case wifi, bluetooth, focus, audio }
    @State private var picker: Picker?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Controls").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)

            // Connectivity cluster, with macOS Control Centre semantics: tapping
            // the circular icon toggles the radio; tapping the rest of the tile
            // expands a picker of networks / devices.
            // Tiles that can't do anything on this Mac stay hidden (no Wi-Fi
            // interface; Focus before it's set up with FDA or a shortcut).
            HStack(spacing: 12) {
                if toggles.wifiPresent {
                    connectTile("Wi-Fi", toggles.wifiName ?? (toggles.wifiOn ? "On" : "Off"), "wifi", .blue,
                                on: toggles.wifiOn, expanded: picker == .wifi,
                                onToggle: { toggles.setWifi(!toggles.wifiOn) },
                                onExpand: { togglePicker(.wifi) })
                }
                connectTile("Bluetooth", toggles.btOn ? "On" : "Off", "bluetooth", .blue,
                            on: toggles.btOn, expanded: picker == .bluetooth,
                            onToggle: { toggles.setBluetooth(!toggles.btOn) },
                            onExpand: { togglePicker(.bluetooth) })
                if toggles.focusAccess || toggles.focusAvailable {
                    connectTile("Focus", focusSubtitle, "moon.fill", Color(red: 0.6, green: 0.45, blue: 0.95),
                                on: toggles.focusOn, expanded: picker == .focus,
                                onToggle: { toggles.toggleFocus() },
                                onExpand: { togglePicker(.focus) })
                }
                connectTile("Appearance", toggles.darkMode ? "Dark" : "Light", "circle.lefthalf.filled",
                            Color(red: 0.45, green: 0.5, blue: 0.6),
                            on: toggles.darkMode, expanded: false,
                            onToggle: { toggles.setDarkMode(!toggles.darkMode) },
                            onExpand: { toggles.setDarkMode(!toggles.darkMode) })
            }

            // Always-present clipped container: the picker unfolds INSIDE it, so
            // the slide never draws over the tile row above.
            VStack(spacing: 0) {
                if picker == .wifi { wifiPicker.transition(.move(edge: .top).combined(with: .opacity)) }
                if picker == .bluetooth { bluetoothPicker.transition(.move(edge: .top).combined(with: .opacity)) }
                if picker == .focus { focusPicker.transition(.move(edge: .top).combined(with: .opacity)) }
            }
            .clipped()

            if model.canControlBacklight {
                FatSlider(value: $brightness, icon: "sun.max.fill", tint: Theme.netUp,
                          onEnded: { model.applyBrightness(Int($0)) })
            }
            if volumeAvailable {
                FatSlider(value: $volume, icon: "speaker.wave.2.fill", tint: Theme.accent,
                          onChanged: { SystemVolume.set(Int($0)) })
            }

            // Sound output — the current device, tap to switch (macOS Sound module).
            if audio.devices.count > 1 {
                Button {
                    if picker == .audio { picker = nil } else { picker = .audio; audio.refresh() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: audioSymbol).font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent).frame(width: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Output").font(.deck(13, .semibold)).foregroundStyle(Theme.textFaint)
                            Text(audio.currentName ?? "—").font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textFaint).rotationEffect(.degrees(picker == .audio ? 180 : 0))
                    }
                    .padding(.horizontal, 14).frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(picker == .audio ? 0.11 : 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.pressable)
                VStack(spacing: 0) {
                    if picker == .audio { audioPicker.transition(.move(edge: .top).combined(with: .opacity)) }
                }.clipped()
            }

            HStack(spacing: 12) {
                actionTile("Minimal", "rectangle.compress.vertical", Theme.accent) { close(); model.setDisplay(.minimal) }
                actionTile("Sleep", "moon.fill", Theme.time) { close(); model.setDisplay(.sleep) }
                actionTile("Screen off", "powersleep", Theme.netDown) { close(); model.turnScreenOff() }
            }

            touchTile

            if model.media.available, model.media.nowPlaying != nil {
                NowPlayingBar(media: model.media, compact: true)
            }
        }
        .padding(20)
        .frame(width: 760)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        .onAppear {
            brightness = Double(model.brightness)
            if let v = SystemVolume.level() { volume = Double(v); volumeAvailable = true }
            toggles.refresh()
            audio.refresh()
        }
        .animation(.easeInOut(duration: 0.2), value: picker)
        .animation(.easeInOut(duration: 0.2), value: audio.devices)
    }

    private var audioSymbol: String {
        audio.devices.first(where: { $0.current })?.symbol ?? "speaker.wave.2.fill"
    }

    private var audioPicker: some View {
        VStack(spacing: 6) {
            ForEach(audio.devices) { device in
                Button { audio.setDefault(device); picker = nil } label: {
                    HStack(spacing: 10) {
                        Image(systemName: device.symbol).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(device.current ? .blue : Theme.textSecondary).frame(width: 24)
                        Text(device.name).font(.deck(14, .semibold))
                            .foregroundStyle(device.current ? .blue : Theme.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        if device.current {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(device.current ? Color.blue.opacity(0.16) : Color.white.opacity(0.03)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
        }
        .padding(.top, 8)
    }

    private func togglePicker(_ p: Picker) {
        picker = (picker == p) ? nil : p
        if picker == .wifi { toggles.scanWifi() }
        if picker == .bluetooth { toggles.loadBluetoothDevices() }
        if picker == .focus { toggles.loadFocusModes() }
    }

    private var focusSubtitle: String {
        if !toggles.focusAvailable { return "Needs a shortcut" }
        return toggles.focusOn ? "On" : "Off"
    }

    /// macOS-style connectivity tile: the coloured circle is the power TOGGLE;
    /// the rest of the tile expands the picker (networks / devices).
    private func connectTile(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color,
                             on: Bool, expanded: Bool,
                             onToggle: @escaping () -> Void, onExpand: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Group {
                    if icon == "bluetooth" {
                        // SF Symbols has no Bluetooth glyph — draw the real mark
                        // (the ᚼ+ᛒ bind-rune) as one continuous stroke.
                        BluetoothGlyph()
                            .stroke(style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                            .frame(width: 13, height: 21)
                    } else {
                        Image(systemName: icon).font(.system(size: 19, weight: .bold))
                    }
                }
                .foregroundStyle(on ? .white : Theme.textFaint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(on ? tint : Color.white.opacity(0.10)))
                .contentShape(Circle())
            }.buttonStyle(.pressable)

            Button(action: onExpand) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(subtitle).font(.deck(12)).foregroundStyle(on ? tint : Theme.textFaint)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textFaint)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 13).frame(maxWidth: .infinity).frame(height: 68)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(expanded ? 0.11 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    // MARK: - Pickers

    private var wifiPicker: some View {
        pickerContainer(title: "Wi-Fi networks", loading: toggles.wifiScanning,
                        empty: toggles.wifiNetworks.isEmpty && !toggles.wifiNamesRedacted,
                        emptyText: toggles.wifiOn ? "No networks found." : "Turn Wi-Fi on to scan.") {
            if toggles.wifiNamesRedacted {
                Button { toggles.requestLocationAccess() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.blue)
                        Text("Networks found, but macOS hides their names — allow Location access to show them")
                            .font(.deck(12, .semibold)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
            ForEach(toggles.wifiNetworks) { net in
                Button { toggles.toggleWifiNetwork(net) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(net.current ? .blue : Theme.textSecondary)
                            .opacity(net.rssi == 0 || net.rssi > -65 ? 1 : net.rssi > -78 ? 0.7 : 0.45)   // signal strength
                            .frame(width: 24)
                        Text(net.ssid).font(.deck(14, .semibold))
                            .foregroundStyle(net.current ? .blue : Theme.textPrimary).lineLimit(1)
                        if net.secure {
                            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                        }
                        Spacer(minLength: 0)
                        if toggles.wifiBusy == net.ssid {
                            ProgressView().controlSize(.small)
                        } else if net.current {
                            Text("Connected").font(.deck(12, .semibold)).foregroundStyle(.blue)
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.blue)
                        } else {
                            Text("Connect").font(.deck(12, .semibold)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(net.current ? Color.blue.opacity(0.16) : Color.white.opacity(0.03)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
            if let err = toggles.wifiError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.deck(12, .semibold)).foregroundStyle(Theme.batteryLow)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 2)
            }
        }
    }

    private var bluetoothPicker: some View {
        pickerContainer(title: "Devices", loading: false,
                        empty: toggles.btDevices.isEmpty,
                        emptyText: toggles.btOn ? "No paired devices." : "Turn Bluetooth on to see devices.") {
            ForEach(toggles.btDevices) { device in
                Button { toggles.toggleBluetoothDevice(device) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: device.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(device.connected ? .blue : Theme.textSecondary)
                            .frame(width: 24)
                        Text(device.name).font(.deck(14, .semibold))
                            .foregroundStyle(device.connected ? .blue : Theme.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        if toggles.btBusy == device.address {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(device.connected ? "Connected" : "Connect")
                                .font(.deck(12, .semibold))
                                .foregroundStyle(device.connected ? .blue : Theme.textFaint)
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(device.connected ? Color.blue.opacity(0.16) : Color.white.opacity(0.03)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
            if let err = toggles.btError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.deck(12, .semibold)).foregroundStyle(Theme.batteryLow)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 2)
            }
        }
    }

    private var focusPicker: some View {
        pickerContainer(title: "Focus", loading: false,
                        empty: toggles.focusModes.isEmpty,
                        emptyText: "No Focus modes found.") {
            ForEach(toggles.focusModes) { mode in
                Button { toggles.activateFocus(mode) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(mode.active ? Color(red: 0.6, green: 0.45, blue: 0.95) : Theme.textSecondary)
                            .frame(width: 24)
                        Text(mode.name).font(.deck(14, .semibold))
                            .foregroundStyle(mode.active ? Color(red: 0.7, green: 0.58, blue: 1.0) : Theme.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        if mode.active {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.6, green: 0.45, blue: 0.95))
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(mode.active ? Color(red: 0.6, green: 0.45, blue: 0.95).opacity(0.16) : Color.white.opacity(0.03)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
            if !toggles.focusAccess {
                Button { toggles.openFullDiskAccessSettings() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.time)
                        Text("Grant Full Disk Access to show your Focus modes and state")
                            .font(.deck(12, .semibold)).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
            if !toggles.focusAvailable {
                Text("Toggling runs a Shortcut — create one named \"Toggle Focus\" (or one per mode, named like the mode) with the Set Focus action.")
                    .font(.deck(11.5)).foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 2)
            }
        }
    }

    private func pickerContainer<C: View>(title: String, loading: Bool, empty: Bool, emptyText: String,
                                          @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title.uppercased()).font(.deckLabel).tracking(Theme.labelTracking).foregroundStyle(Theme.textFaint)
                if loading { ProgressView().controlSize(.small) }
            }
            if empty && !loading {
                Text(emptyText).font(.deck(13)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 10)
            } else if empty {
                // Same footprint as a row while scanning, so the container doesn't
                // hug and then jump to full width when results land.
                Text("Scanning…").font(.deck(13)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 10)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) { rows() }
                }
                .frame(maxHeight: 210)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func close() { model.closeControlCenter() }

    private func actionTile(_ title: String, _ icon: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                Text(title).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.pressable)
    }

    private var touchTile: some View {
        let on = model.touchStatus != .off
        return Button(action: model.toggleTouch) {
            HStack(spacing: 14) {
                Image(systemName: "hand.tap.fill").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(on ? Theme.battery : Theme.textFaint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Touch").font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(on ? "On" : "Off").font(.deck(13)).foregroundStyle(on ? Theme.battery : Theme.textFaint)
                }
                Spacer()
                ToggleDot(on: on)
            }
            .padding(.horizontal, 16).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }
}

/// The Bluetooth logo as a path: the vertical stem with the two right-hand
/// chevron points and the two diagonals crossing from the left — drawn exactly
/// like the trademark rune, since SF Symbols doesn't include one.
private struct BluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height)
        }
        var p = Path()
        p.move(to: pt(0.06, 0.74))
        p.addLine(to: pt(0.94, 0.26))
        p.addLine(to: pt(0.52, 0.02))
        p.addLine(to: pt(0.52, 0.98))
        p.addLine(to: pt(0.94, 0.74))
        p.addLine(to: pt(0.06, 0.26))
        return p
    }
}

/// A fat, drag-anywhere slider — big enough to grab on a touchscreen. The fill and
/// icon live inside the track. `onChanged` fires live (cheap side-effects like
/// volume); `onEnded` fires on release (slow ones like DDC brightness).
struct FatSlider: View {
    @Binding var value: Double   // 0…100
    var icon: String
    var tint: Color
    var onChanged: ((Double) -> Void)? = nil
    var onEnded: ((Double) -> Void)? = nil

    var body: some View {
        GeometryReader { g in
            let frac = CGFloat(min(1, max(0, value / 100)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(56, g.size.width * frac))
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .padding(.leading, 18)
                HStack {
                    Spacer()
                    Text("\(Int(value))").font(.readout(18, .bold)).foregroundStyle(.white.opacity(0.9)).padding(.trailing, 18)
                }
            }
            .frame(height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(1, max(0, v.location.x / g.size.width))
                        value = Double(f) * 100
                        onChanged?(value)
                    }
                    .onEnded { _ in onEnded?(value) }
            )
        }
        .frame(height: 58)
    }
}
