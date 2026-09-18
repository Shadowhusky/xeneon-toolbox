import SwiftUI

/// Observes the focus timer in isolation so only this tiny view re-renders when
/// it completes (not the whole panel every second). Shows the "time's up" alert.
struct FocusDoneGate: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        ZStack {
            if timer.justFinished {
                FocusDoneOverlay { timer.dismissFinished() }
            }
        }
        .animation(Motion.pop, value: timer.justFinished)
    }
}

/// The full-screen "focus session complete" alert.
private struct FocusDoneOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ModalScaffold(onDismiss: onDismiss) {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46)).foregroundStyle(Theme.accent)
                    .deckGlow(Theme.accent, strength: 1)
                VStack(spacing: 6) {
                    Text("Focus session complete").font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Nice work. Time for a break.").font(.deck(15)).foregroundStyle(Theme.textSecondary)
                }
                PrimaryButton(title: "Done", height: 54, action: onDismiss).frame(maxWidth: .infinity)
            }
            .padding(30).frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 24)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        }
    }
}

/// A compact running-timer pill for the ambient screen — glance at your desk and
/// see how much focus time is left. Only present while the timer is running.
struct FocusTimerPill: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        if timer.running {
            HStack(spacing: 9) {
                Image(systemName: "timer").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                Text(timer.clock).font(.readout(16, .semibold)).foregroundStyle(Theme.textPrimary)
                Text("focus").font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14).frame(height: 38)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        }
    }
}
