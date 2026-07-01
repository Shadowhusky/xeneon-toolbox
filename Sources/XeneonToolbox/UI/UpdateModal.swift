import SwiftUI

/// Watches the update checker and presents the modal when an update is available,
/// unless the panel is in immersive fullscreen (don't interrupt a game).
struct UpdateGate: View {
    @ObservedObject var updater: UpdateChecker
    var fullscreen: Bool

    var body: some View {
        ZStack {
            if let info = updater.available, !fullscreen {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { updater.ignoreThisTime(info) }
                UpdateModal(updater: updater, info: info)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: updater.available)
    }
}

struct UpdateModal: View {
    @ObservedObject var updater: UpdateChecker
    let info: UpdateInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.accent)
                    .deckGlow(Theme.accent, strength: 0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)
                    Text(info.name).font(.deck(13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                versionPill
            }
            Rectangle().fill(LinearGradient(colors: [Theme.accent.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5).padding(.top, 16).padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                MarkdownBubble(text: info.notes.isEmpty ? "_No release notes provided._" : info.notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.bottom, 16)

            switch updater.install {
            case .working(let message):
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text(message).font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(height: 48)
            case .failed(let message):
                HStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.deck(13)).foregroundStyle(Theme.batteryLow).lineLimit(2)
                    Spacer(minLength: 0)
                    textButton("Later", color: Theme.textSecondary) { updater.ignoreThisTime(info) }
                    updateButton("Open download") { updater.openDownload(info) }
                }
            case .idle:
                HStack(spacing: 12) {
                    textButton("Skip this version", color: Theme.textFaint) { updater.skip(info) }
                    Spacer(minLength: 0)
                    textButton("Later", color: Theme.textSecondary) { updater.ignoreThisTime(info) }
                    updateButton(updater.canSelfInstall ? "Update" : "Download") { updater.update(info) }
                }
            }
        }
        .padding(28)
        .frame(width: 620, height: 540)
        .background(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var versionPill: some View {
        HStack(spacing: 7) {
            Text("v\(updater.currentVersion ?? "—")").foregroundStyle(Theme.textFaint)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
            Text("v\(info.version)").foregroundStyle(Theme.accent)
        }
        .font(.readout(13, .semibold))
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
    }

    private func updateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.down.circle.fill")
                .font(.deck(16, .bold)).foregroundStyle(Color(red: 0.02, green: 0.13, blue: 0.16))
                .padding(.horizontal, 22).frame(height: 48)
                .background(Capsule().fill(Theme.accent))
                .deckGlow(Theme.accent, strength: 0.5)
        }.buttonStyle(.pressable)
    }

    private func textButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.deck(15, .semibold)).foregroundStyle(color)
                .padding(.horizontal, 16).frame(height: 48)
                .background(Capsule().fill(Color.white.opacity(0.05)))
        }.buttonStyle(.pressable)
    }
}
