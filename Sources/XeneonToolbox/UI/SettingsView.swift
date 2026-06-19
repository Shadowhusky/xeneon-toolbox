import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ToolboxModel
    var onClose: () -> Void = {}
    @State private var confirmClear = false

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
