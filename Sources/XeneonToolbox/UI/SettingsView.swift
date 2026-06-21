import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ToolboxModel
    var onClose: () -> Void = {}
    @State private var confirmClear = false
    @State private var sliderValue: Double = 90

    private func dismiss() { onClose() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.deck(24, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.textFaint)
                }.buttonStyle(.pressable)
            }
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Touch calibration", "Use these if taps land mirrored or rotated.") {
                        Toggle("Flip horizontal", isOn: $model.flipX)
                        Toggle("Flip vertical", isOn: $model.flipY)
                        Toggle("Swap axes", isOn: $model.swapXY)
                    }
                    section("Display", "Tap the screen to wake from these.") {
                        HStack(spacing: 12) {
                            modeButton("Minimal", "rectangle.compress.vertical") { model.setDisplay(.minimal); dismiss() }
                            modeButton("Sleep", "moon.fill") { model.setDisplay(.sleep); dismiss() }
                        }
                    }
                    section("Backlight", "The Edge is an LCD — its backlight is always on, so a black screen saves no power. Turn the backlight down (or off) to actually save power and spare the panel.") {
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
                            Text("Install m1ddc to control the backlight:  brew install m1ddc")
                                .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.textFaint)
                        }
                        Button { model.turnScreenOff(); dismiss() } label: {
                            Label("Turn screen off", systemImage: "power.circle.fill")
                                .font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        }.buttonStyle(.pressable)
                        Text(model.canControlBacklight ? "Cuts the backlight to its minimum. Tap the screen to wake." : "Shows a black screen and pauses monitoring. Tap to wake. (Backlight stays on without m1ddc.)")
                            .font(.deck(12)).foregroundStyle(Theme.textFaint)
                    }
                    section("Assistant", "Conversations are stored on this Mac.") {
                        Button { confirmClear = true } label: {
                            Label("Clear all conversations", systemImage: "trash")
                                .font(.deck(15, .semibold)).foregroundStyle(Theme.batteryLow)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.batteryLow.opacity(0.12)))
                        }.buttonStyle(.pressable)
                        if confirmClear {
                            HStack(spacing: 10) {
                                Text("Delete every conversation?").font(.deck(14)).foregroundStyle(Theme.textSecondary)
                                Button("Delete") { model.agent.clearAll(); confirmClear = false }
                                    .font(.deck(14, .bold)).foregroundStyle(Theme.batteryLow).buttonStyle(.pressable)
                                Button("Cancel") { confirmClear = false }
                                    .font(.deck(14)).foregroundStyle(Theme.textFaint).buttonStyle(.pressable)
                            }
                        }
                    }
                    section("About", nil) {
                        labelRow("Xeneon Toolbox", "for the Corsair Xeneon Edge")
                        labelRow("Touch", model.touchStatus == .active ? "Active" : "Inactive")
                        labelRow("Repo", "github.com/Shadowhusky/xeneon-toolbox")
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 560, height: 560)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func section<C: View>(_ title: String, _ subtitle: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.deck(12, .bold)).tracking(1.4).foregroundStyle(Theme.accent)
            if let s = subtitle { Text(s).font(.deck(13)).foregroundStyle(Theme.textFaint) }
            content().font(.deck(15)).foregroundStyle(Theme.textPrimary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func modeButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        }.buttonStyle(.pressable)
    }

    private func labelRow(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundStyle(Theme.textSecondary); Spacer(); Text(b).foregroundStyle(Theme.textFaint) }
            .font(.deck(14))
    }
}
