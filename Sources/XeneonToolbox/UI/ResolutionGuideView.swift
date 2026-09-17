import SwiftUI

/// The resolution guide: shown over everything when the Edge is in a scaled mode.
/// One tap switches to 2560 × 720 (with a short Undo window); the manual steps
/// cover Macs where the native timing is hidden from the mode list.
struct ResolutionGuideView: View {
    let issue: DisplayIssue
    var appliedAt: Date?
    var failed = false
    var onApply: () -> Void
    var onUndo: () -> Void
    var onKeep: () -> Void
    var onLater: () -> Void
    var onOpenSettings: () -> Void

    private let undoWindow: TimeInterval = 15

    var body: some View {
        ModalScaffold(dim: 0.7, onDismiss: {}) {
            VStack(alignment: .leading, spacing: 20) {
                if let appliedAt {
                    applied(appliedAt)
                } else {
                    header
                    actions
                    manualSteps
                }
            }
            .padding(28)
            .frame(width: 940)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .onAppear {
            if let appliedAt, Date().timeIntervalSince(appliedAt) > undoWindow { onKeep() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.warning)
                .deckGlow(Theme.warning, strength: 0.7)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Xeneon Edge isn't at its native resolution")
                    .font(.deck(26, .bold)).foregroundStyle(Theme.textPrimary)
                Text(failed
                     ? "The automatic switch didn't take. Set it by hand in Display Settings — it only needs doing once."
                     : "macOS picked \(issue.currentLabel). The panel is 2560 × 720, so the picture is being scaled and the Toolbox can't fit the strip.")
                    .font(.deck(16)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if issue.recommended != nil, !failed {
                Button(action: onApply) {
                    Label("Use 2560 × 720", systemImage: "wand.and.stars")
                        .font(.deck(17, .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 24).frame(height: 56)
                        .background(Capsule().fill(Theme.accent))
                        .contentShape(Capsule())
                }.buttonStyle(.pressable)
            }
            Button(action: onOpenSettings) {
                Label("Open Display Settings", systemImage: "arrow.up.forward.app")
                    .font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 22).frame(height: 56)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                    .contentShape(Capsule())
            }.buttonStyle(.pressable)
            Spacer(minLength: 0)
            Button(action: onLater) {
                Text("Later").font(.deck(16, .semibold)).foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 22).frame(height: 56).contentShape(Rectangle())
            }.buttonStyle(.pressable)
        }
    }

    private var manualSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.recommended == nil || failed ? "SET IT BY HAND" : "OR SET IT BY HAND")
                .font(.deckLabel).tracking(Theme.labelTracking).foregroundStyle(Theme.textFaint)
            HStack(spacing: 10) {
                step(1, "Choose XENEON EDGE in Displays")
                step(2, "Hold ⌥ and click Scaled to show all resolutions")
                step(3, "Pick 2560 × 720")
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.readout(14, .bold)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.accent.opacity(0.16)))
            Text(text).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func applied(_ at: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((undoWindow - ctx.date.timeIntervalSince(at)).rounded(.up)))
            HStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Theme.battery)
                    .deckGlow(Theme.battery, strength: 0.7).frame(width: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Switched to 2560 × 720").font(.deck(24, .bold)).foregroundStyle(Theme.textPrimary)
                    Text(left > 0 ? "If the panel looks wrong, undo within \(left) s." : "Keeping this resolution.")
                        .font(.deck(15)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if left > 0 {
                    Button(action: onUndo) {
                        Text("Undo").font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 22).frame(height: 56)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.pressable)
                }
                Button(action: onKeep) {
                    Text("Keep").font(.deck(17, .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 26).frame(height: 56)
                        .background(Capsule().fill(Theme.battery))
                        .contentShape(Capsule())
                }.buttonStyle(.pressable)
            }
            .onChange(of: left) { if left == 0 { onKeep() } }
        }
    }
}
