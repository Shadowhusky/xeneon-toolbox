import SwiftUI

/// Watches the update checker and presents the modal when an update is available,
/// unless the panel is in immersive fullscreen (don't interrupt the user).
struct UpdateGate: View {
    @ObservedObject var updater: UpdateChecker
    var fullscreen: Bool

    var body: some View {
        ZStack {
            if let info = updater.available, !fullscreen {
                ModalScaffold(onDismiss: { updater.ignoreThisTime(info) }) {
                    UpdateModal(updater: updater, info: info)
                }
            } else if updater.showWhatsNew, let info = updater.justUpdated {
                ModalScaffold(onDismiss: { updater.dismissWhatsNew() }) {
                    UpdateModal(updater: updater, info: info, notesOnly: true)
                }
            }
        }
        .animation(Motion.pop, value: updater.available)
        .animation(Motion.pop, value: updater.showWhatsNew)
    }
}

/// The quiet notices: a staged update ("installs when you're away") and, after a
/// relaunch, "updated". Neither blocks anything and both fade on their own.
struct UpdateToasts: View {
    @ObservedObject var updater: UpdateChecker
    var fullscreen: Bool

    var body: some View {
        VStack {
            if let s = updater.staged, updater.showReadyNotice, !fullscreen {
                toast(icon: "arrow.down.circle.fill", title: "Version \(s.version) is ready",
                      detail: updater.policy == .automatic ? "It installs itself the next time you're away." : "Restart whenever suits you.",
                      action: "Restart now", perform: { updater.installNow() },
                      dismiss: { updater.showReadyNotice = false })
                .task { try? await Task.sleep(for: .seconds(25)); updater.showReadyNotice = false }
            } else if let u = updater.justUpdated, !updater.showWhatsNew, !fullscreen {
                toast(icon: "sparkles", title: "Updated to version \(u.version)", detail: "Everything is back where it was.",
                      action: "What's new", perform: { updater.showWhatsNew = true },
                      dismiss: { updater.dismissWhatsNew() })
                .task { try? await Task.sleep(for: .seconds(40)); if !updater.showWhatsNew { updater.dismissWhatsNew() } }
            }
        }
        .padding(.bottom, 16)
        .animation(Motion.pop, value: updater.showReadyNotice)
        .animation(Motion.pop, value: updater.justUpdated)
    }

    private func toast(icon: String, title: String, detail: String, action: String,
                       perform: @escaping () -> Void, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.deck(13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 16)
            PrimaryButton(title: action, height: 40, action: perform)
            CircleIconButton(icon: "xmark", size: 40, action: dismiss)
        }
        .padding(.leading, 16).padding(.trailing, 12).frame(height: 68)
        .frame(maxWidth: 720)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.tileBottom.opacity(0.9)))
        .bezel(corner: 20)
        .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
        .transition(.riseUp)
    }
}

struct UpdateModal: View {
    @ObservedObject var updater: UpdateChecker
    let info: UpdateInfo
    var notesOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: notesOnly ? "sparkles" : "arrow.down.circle.fill")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.accent)
                    .deckGlow(Theme.accent, strength: 0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notesOnly ? "What's new" : "Update available").font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(info.name).font(.deck(13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                versionPill
            }
            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.top, 16).padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                MarkdownBubble(text: info.notes.isEmpty ? "_No release notes provided._" : info.notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.bottom, 16)

            if notesOnly {
                HStack { Spacer(minLength: 0); PrimaryButton(title: "Done", height: 48) { updater.dismissWhatsNew() } }
            } else {
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
                    GhostButton(title: "Later", tint: Theme.textSecondary, height: 48) { updater.ignoreThisTime(info) }
                    PrimaryButton(title: "Open download", icon: "arrow.down.circle.fill", height: 48) { updater.openDownload(info) }
                }
            case .idle:
                HStack(spacing: 12) {
                    GhostButton(title: "Skip this version", tint: Theme.textFaint, height: 48) { updater.skip(info) }
                    Spacer(minLength: 0)
                    GhostButton(title: "Later", tint: Theme.textSecondary, height: 48) { updater.ignoreThisTime(info) }
                    PrimaryButton(title: updater.staged?.version == info.version ? "Restart to update"
                                         : (updater.canSelfInstall ? "Update" : "Download"),
                                  icon: "arrow.down.circle.fill", height: 48) { updater.update(info) }
                }
            }
            }
        }
        .padding(28)
        .frame(width: 620, height: 540)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.background))
        .bezel(corner: 26)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var versionPill: some View {
        HStack(spacing: 7) {
            if !notesOnly {
                Text("v\(updater.currentVersion ?? "—")").foregroundStyle(Theme.textFaint)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
            }
            Text("v\(info.version)").foregroundStyle(Theme.accent)
        }
        .font(.readout(13, .semibold))
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
    }

}
