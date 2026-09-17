import SwiftUI

/// What the normal (non-kiosk) window shows while no Xeneon Edge is connected.
struct NoEdgeView: View {
    var onQuit: () -> Void

    var body: some View {
        ZStack {
            DeckBackground()
            HStack(spacing: 40) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
                        .frame(width: 210, height: 78)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5))
                        .deckGlow(Theme.accent, strength: 1.2)
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your Xeneon Edge").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
                    Text("Plug the panel in over USB-C. The Toolbox moves onto it automatically and takes over touch.")
                        .font(.deck(15)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        DeckSpinner(size: 22)
                        Text("Looking for the panel…").font(.deck(13, .medium)).foregroundStyle(Theme.textFaint)
                        Spacer(minLength: 0)
                        Button(action: onQuit) {
                            Text("Quit").font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 18).frame(height: 44)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                                .contentShape(Capsule())
                        }.buttonStyle(.pressable)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: 560)
            }
            .padding(40)
        }
    }
}
