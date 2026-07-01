import SwiftUI
import AppKit
import CoreImage

struct SettingsView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var remote: RemoteServer
    @ObservedObject var updater: UpdateChecker
    var onClose: () -> Void = {}
    @State private var confirmClear = false
    @State private var sliderValue: Double = 90
    @State private var configStatus = ""

    private func dismiss() { onClose() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.deck(30, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }.buttonStyle(.pressable)
            }
            Rectangle().fill(LinearGradient(colors: [Theme.accent.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5).padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
              HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
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
                    section("Now Playing", "Show music controls on the dashboard and idle screen.", "music.note", Theme.memory) {
                        Toggle("Show Now Playing", isOn: $model.showNowPlaying)
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
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 18) {
                    section("Remote control", "Control the Edge from your phone or PC on the same network.", "antenna.radiowaves.left.and.right", Theme.netDown) {
                        Toggle("Enable remote control", isOn: Binding(get: { model.remoteEnabled }, set: { model.setRemote($0) }))
                        if model.remoteEnabled {
                            if remote.urls.isEmpty {
                                Text(remote.running ? "Running on port \(remote.port)" : "Starting…")
                                    .font(.deck(13)).foregroundStyle(Theme.textFaint)
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    if let qr = Self.qrImage(remote.urls[0]) {
                                        Image(nsImage: qr).interpolation(.none).resizable()
                                            .frame(width: 128, height: 128).padding(9)
                                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Scan with your phone, or open:").font(.deck(13)).foregroundStyle(Theme.textSecondary)
                                        ForEach(remote.urls, id: \.self) { u in
                                            Text(u).font(.system(size: 15, design: .monospaced))
                                                .foregroundStyle(Theme.accent).textSelection(.enabled)
                                                .lineLimit(1).minimumScaleFactor(0.5)
                                        }
                                        Text("Anyone on the same Wi-Fi can use it.").font(.deck(12)).foregroundStyle(Theme.textFaint)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
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
                    section("Software update", "Checks GitHub for new versions automatically.", "arrow.down.circle.fill", Theme.netDown) {
                        labelRow("Current version", "v\(updater.currentVersion ?? "—")")
                        Button { updater.check(manual: true) } label: {
                            Label(updater.checking ? "Checking…" : "Check for updates", systemImage: "arrow.clockwise")
                                .font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        }.buttonStyle(.pressable).disabled(updater.checking)
                        if !updater.statusLine.isEmpty {
                            Text(updater.statusLine).font(.deck(12)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    section("About", nil, "info.circle.fill", Theme.time) {
                        labelRow("Xeneon Toolbox", "for the Corsair Xeneon Edge")
                        touchStatusRow
                        labelRow("Repo", "github.com/Shadowhusky/xeneon-toolbox")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
              }
            }
        }
        .padding(30)
        .frame(width: 1240, height: 660)
        .background(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func section<C: View>(_ title: String, _ subtitle: String?, _ icon: String, _ accent: Color,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(accent)
                    Text(title.uppercased()).font(.deck(14, .bold)).tracking(1.4).foregroundStyle(accent)
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
        return HStack {
            Text("Touch").foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(active ? Theme.battery : Theme.batteryLow).frame(width: 8, height: 8)
                    .deckGlow(active ? Theme.battery : Theme.batteryLow, strength: 0.6)
                Text(active ? "Active" : "Inactive").foregroundStyle(active ? Theme.battery : Theme.batteryLow)
            }
        }
        .font(.deck(14))
    }
}
