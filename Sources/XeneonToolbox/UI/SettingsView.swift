import SwiftUI
import ToolboxKit
import AppKit
import CoreImage
import XeneonTouchDriver

struct SettingsView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var remote: RemoteServer
    @ObservedObject var updater: UpdateChecker
    var onClose: () -> Void = {}
    @State private var confirmClear = false
    @State private var sliderValue: Double = 90
    @State private var configStatus = ""
    @State private var edge: EdgeDisplay? = EdgeScreen.current()

    private func dismiss() { onClose() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.deck(26, .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                CircleIconButton(icon: "xmark", size: 44) { dismiss() }
            }
            .padding(.bottom, 18)

            // ScrollView content doesn't lay out in the off-screen renderer.
            ScrollOrStatic(scrolls: !model.exportMode) {
              HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    section("Xeneon Edge", nil, "rectangle.bottomthird.inset.filled", Theme.accent) {
                        edgeRow
                        touchStatusRow
                    }
                    section("Touch calibration", "Use these if taps land mirrored or rotated.", "hand.tap.fill", Theme.accent) {
                        Toggle("Flip horizontal", isOn: $model.flipX)
                        Toggle("Flip vertical", isOn: $model.flipY)
                        Toggle("Swap axes", isOn: $model.swapXY)
                    }
                    section("Display", "Tap the screen to wake from these.", "rectangle.compress.vertical", Theme.accent) {
                        HStack(spacing: 12) {
                            modeButton("Minimal", "rectangle.compress.vertical") { model.setDisplay(.minimal); dismiss() }
                            modeButton("Sleep", "moon.fill") { model.setDisplay(.sleep); dismiss() }
                        }
                    }
                    section("Now Playing", "Show the player bar on the ambient screen. The dashboard has its own Now Playing tile.", "music.note", Theme.memory) {
                        Toggle("Show Now Playing on the ambient screen", isOn: $model.showNowPlaying)
                    }
                    section("Screen", "Dim the screen, or turn it off to save power.", "sun.max.fill", Theme.netUp) {
                        if model.canControlBacklight {
                            HStack(spacing: 12) {
                                Image(systemName: "sun.min.fill").foregroundStyle(Theme.textFaint)
                                Slider(value: $sliderValue, in: 0...100) { editing in
                                    if !editing { model.applyBrightness(Int(sliderValue)) }
                                }
                                Image(systemName: "sun.max.fill").foregroundStyle(Theme.textSecondary)
                                Text("\(Int(sliderValue))%").font(.readout(14, .semibold)).foregroundStyle(Theme.textSecondary).frame(width: 46, alignment: .trailing)
                            }
                            .onAppear { sliderValue = Double(model.brightness) }
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle.fill").foregroundStyle(Theme.netUp)
                                Text("Brightness can't be adjusted on this Mac.").font(.deck(13)).foregroundStyle(Theme.textSecondary)
                                Spacer(minLength: 0)
                            }
                        }
                        Button { model.turnScreenOff(); dismiss() } label: {
                            Label("Turn screen off", systemImage: "power.circle.fill")
                                .font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        }.buttonStyle(.pressable)
                        Text("Tap the screen to turn it back on.")
                            .font(.deck(12)).foregroundStyle(Theme.textFaint)
                    }
                    section("Weather location", "IP lookup is only ISP-accurate — pin your real city here.", "location.fill", Theme.time) {
                        WeatherLocationPicker(weather: model.weather)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 18) {
                    section("Remote control", "Control the Edge from your phone or PC on the same network.", "antenna.radiowaves.left.and.right", Theme.netDown) {
                        Toggle("Enable remote control", isOn: Binding(get: { model.remoteEnabled }, set: { model.setRemote($0) }))
                        if model.remoteEnabled {
                            let urls = remote.displayURLs
                            if urls.isEmpty {
                                Text(remote.running ? "Running on port \(remote.port)" : "Starting…")
                                    .font(.deck(13)).foregroundStyle(Theme.textFaint)
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    if let qr = Self.qrImage(urls[0]) {
                                        Image(nsImage: qr).interpolation(.none).resizable()
                                            .frame(width: 128, height: 128).padding(9)
                                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Scan with your phone, or open:").font(.deck(13)).foregroundStyle(Theme.textSecondary)
                                        ForEach(urls, id: \.self) { u in
                                            Text(u).font(.system(size: 15, design: .monospaced))
                                                .foregroundStyle(Theme.accent).textSelection(.enabled)
                                                .lineLimit(1).minimumScaleFactor(0.5)
                                        }
                                        Text("The link includes a private access key. Share it only with people you trust.")
                                            .font(.deck(12)).foregroundStyle(Theme.textFaint)
                                        GhostButton(title: "New link", icon: "arrow.triangle.2.circlepath", tint: Theme.textSecondary, height: 40) {
                                            remote.regenerateToken()
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    section("Permissions", "What macOS must allow, and where to turn each one on.", "lock.shield.fill", Theme.ice) {
                        PermissionsList()
                    }
                    section("Assistant", "Conversations are stored on this Mac.", "sparkles", Theme.batteryLow) {
                        if confirmClear {
                            HStack(spacing: 10) {
                                Text("Delete every conversation?").font(.deck(14)).foregroundStyle(Theme.textSecondary)
                                Spacer(minLength: 0)
                                Button { model.agent.clearAll(); confirmClear = false } label: {
                                    Text("Delete").font(.deck(14, .bold)).foregroundStyle(Theme.batteryLow)
                                        .padding(.horizontal, 18).frame(height: 44)
                                        .background(Capsule().fill(Theme.batteryLow.opacity(0.16)))
                                }.buttonStyle(.pressable)
                                Button { confirmClear = false } label: {
                                    Text("Cancel").font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, 18).frame(height: 44)
                                        .background(Capsule().fill(Color.white.opacity(0.06)))
                                }.buttonStyle(.pressable)
                            }
                        } else {
                            Button { confirmClear = true } label: {
                                Label("Clear all conversations", systemImage: "trash")
                                    .font(.deck(15, .semibold)).foregroundStyle(Theme.batteryLow)
                                    .padding(.horizontal, 16).frame(height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.batteryLow.opacity(0.12)))
                            }.buttonStyle(.pressable)
                        }
                    }
                    section("Configuration", "Back up your layout, deck and preferences to iCloud, or restore them.", "icloud.fill", Theme.disk) {
                        HStack(spacing: 10) {
                            modeButton("Back up to iCloud", "icloud.and.arrow.up") {
                                switch ConfigBackup.backup() { case .ok(let m): configStatus = m; case .fail(let m): configStatus = m }
                            }
                            modeButton("Restore", "icloud.and.arrow.down") {
                                switch ConfigBackup.restore() {
                                case .ok(let m):
                                    configStatus = m
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { ConfigBackup.relaunch() }
                                case .fail(let m): configStatus = m
                                }
                            }
                        }
                        if !configStatus.isEmpty { Text(configStatus).font(.deck(12)).foregroundStyle(Theme.textFaint) }
                    }
                    section("Software update", "New versions download in the background and install when you're away.", "arrow.down.circle.fill", Theme.netDown) {
                        SoftwareUpdateControls(updater: updater)
                    }
                    section("About", nil, "info.circle.fill", Theme.time) {
                        labelRow("Xeneon Toolbox", "for the Corsair Xeneon Edge")
                        labelRow("Repo", "github.com/Shadowhusky/xeneon-toolbox")
                        labelRow("Logs", "~/.config/xeneon-toolbox (app.log · crash-*.log)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
              }
            }
        }
        .padding(30)
        .frame(width: 1240, height: 660)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.background))
        .bezel(corner: 26)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: model.displayIssue) { edge = EdgeScreen.current() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            edge = EdgeScreen.current()
        }
    }

    /// The panel and its mode, with a Fix when macOS has it scaled.
    private var edgeRow: some View {
        HStack(spacing: 10) {
            Text("Display").foregroundStyle(Theme.textSecondary)
            Spacer()
            if let e = edge {
                Text("\(e.modeLabel)\(e.refreshHz > 0 ? String(format: " @ %.0f Hz", e.refreshHz) : "")")
                    .font(.readout(14, .semibold)).foregroundStyle(e.isNativeMode ? Theme.textPrimary : Theme.warning)
                if e.isNativeMode {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.battery)
                } else {
                    Button { model.displayIssue = DisplayModeAdvisor.check(ignoringDismissal: true) } label: {
                        Text("Fix").font(.deck(13, .semibold)).foregroundStyle(Theme.backgroundEdge)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(Theme.warning))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.pressable)
                }
            } else {
                Text("Not connected").foregroundStyle(Theme.textFaint)
            }
        }
        .font(.deck(14))
    }

    private struct ScrollOrStatic<Content: View>: View {
        let scrolls: Bool
        @ViewBuilder var content: Content
        var body: some View {
            if scrolls { ScrollView(showsIndicators: false) { content } }
            else { content.frame(maxHeight: .infinity, alignment: .top).clipped() }
        }
    }

    private func section<C: View>(_ title: String, _ subtitle: String?, _ icon: String, _ accent: Color,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(accent.opacity(0.14)))
                    Text(title).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                }
                Rectangle().fill(LinearGradient(colors: [accent.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            }
            if let s = subtitle { Text(s).font(.deck(14)).foregroundStyle(Theme.textSecondary) }
            content().font(.deck(16)).foregroundStyle(Theme.textPrimary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [accent.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 280))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LinearGradient(colors: [accent.opacity(0.22), Theme.stroke], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func modeButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        }.buttonStyle(.pressable)
    }

    private func labelRow(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundStyle(Theme.textSecondary); Spacer(); Text(b).foregroundStyle(Theme.textFaint) }
            .font(.deck(15))
    }

    static func qrImage(_ string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    private var touchStatusRow: some View {
        let active = model.touchStatus == .active
        return HStack(spacing: 10) {
            Text("Touch").foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(active ? Theme.battery : Theme.batteryLow).frame(width: 8, height: 8)
                    .deckGlow(active ? Theme.battery : Theme.batteryLow, strength: 0.6)
                Text(active ? "Active" : (model.touchOn ? "Searching" : "Off"))
                    .foregroundStyle(active ? Theme.battery : Theme.batteryLow)
                if let at = model.lastTouchInputAt {
                    Text("· last input \(Self.age(at))").foregroundStyle(Theme.textFaint)
                }
            }
            Button { model.restartTouch() } label: {
                Label("Restart touch", systemImage: "arrow.clockwise")
                    .font(.deck(13, .semibold)).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .contentShape(Capsule())
            }.buttonStyle(.pressable)
        }
        .font(.deck(14))
    }

    private static func age(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "\(s / 3600) h ago"
    }
}

/// Search-and-pin the weather city, or return to automatic IP location.
struct WeatherLocationPicker: View {
    @ObservedObject var weather: WeatherService
    @State private var query = ""
    @State private var results: [WeatherLocation] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: weather.customPlace == nil ? "location.viewfinder" : "mappin.circle.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.time)
                Text(currentLabel).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if weather.customPlace != nil {
                    Button { weather.setPlace(nil); query = ""; results = [] } label: {
                        Text("Use automatic").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .contentShape(Capsule())
                    }.buttonStyle(.pressable)
                }
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textFaint)
                TextField("Search for your city", text: $query)
                    .textFieldStyle(.plain).font(.deck(15)).foregroundStyle(Theme.textPrimary)
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .onChange(of: query) { search() }

            ForEach(results) { r in
                Button { weather.setPlace(r); query = ""; results = [] } label: {
                    HStack(spacing: 8) {
                        Text(r.name).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(r.region).font(.deck(12)).foregroundStyle(Theme.textFaint).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
        }
    }

    private var currentLabel: String {
        if let p = weather.customPlace { return "\(p.name) · pinned" }
        return "Automatic — \(weather.weather?.city.isEmpty == false ? weather.weather!.city : "detecting…")"
    }

    private func search() {
        searchTask?.cancel()
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; searching = false; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)   // debounce typing
            guard !Task.isCancelled else { return }
            searching = true
            let found = await WeatherService.searchCities(q)
            if !Task.isCancelled { results = found }
            searching = false
        }
    }
}

private struct SoftwareUpdateControls: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current version").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("v\(updater.currentVersion ?? "—")").font(.readout(14, .semibold)).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 8) {
                policyButton("Automatic", .automatic)
                policyButton("Ask first", .notify)
                policyButton("Off", .off)
            }
            if let s = updater.staged {
                PrimaryButton(title: "Restart to update to v\(s.version)", icon: "arrow.down.circle.fill", height: 44) {
                    updater.installNow()
                }
                .frame(maxWidth: .infinity)
            }
            GhostButton(title: updater.checking ? "Checking…" : "Check for updates", icon: "arrow.clockwise",
                        tint: Theme.textPrimary, height: 44) { updater.check(manual: true) }
                .frame(maxWidth: .infinity)
                .disabled(updater.checking)
            if !updater.statusLine.isEmpty {
                Text(updater.statusLine).font(.deck(12)).foregroundStyle(Theme.textFaint)
            }
        }
    }

    private func policyButton(_ title: String, _ value: UpdatePolicy) -> some View {
        let on = updater.policy == value
        return Button { updater.policy = value } label: {
            Text(title).font(.deck(14, .semibold))
                .foregroundStyle(on ? Theme.backgroundEdge : Theme.textSecondary)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Capsule().fill(on ? Theme.accent : Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.25 : 0.06), lineWidth: 1))
                .contentShape(Capsule())
        }.buttonStyle(.pressable)
    }
}
