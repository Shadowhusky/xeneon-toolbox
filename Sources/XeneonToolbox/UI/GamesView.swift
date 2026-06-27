import SwiftUI

struct GamesView: View {
    @ObservedObject var model: ToolboxModel
    @State private var reloadID = UUID()
    @State private var loadState: WebLoadState = .loading

    enum Game: String, CaseIterable {
        case rhythm = "Rhythm Plus"
        var key: String { "rhythm" }
        var url: URL { URL(string: "https://v2.rhythm-plus.com/")! }
    }

    private var selected: Game { .rhythm }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Games").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(selected.rawValue)
                    .font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                Button { reload() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary).frame(width: 46, height: 46)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                }
                .buttonStyle(.pressable)
            }
            ZStack {
                WebGameView(url: selected.url, state: $loadState)
                    .id("\(selected.key)-\(reloadID)")
                if loadState == .loading { loadingOverlay }
                if loadState == .failed { errorOverlay }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.stroke],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: loadState)
        }
        .onChange(of: selected.key) { loadState = .loading }
    }

    private func reload() { loadState = .loading; reloadID = UUID() }

    private var paneFill: some View {
        LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)
    }

    private var loadingOverlay: some View {
        ZStack {
            paneFill
            VStack(spacing: 20) {
                DeckSpinner()
                Text("Loading \(selected.rawValue)…").font(.deck(16, .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var errorOverlay: some View {
        ZStack {
            paneFill
            VStack(spacing: 18) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.batteryLow).deckGlow(Theme.batteryLow, strength: 0.6)
                Text("Couldn't load \(selected.rawValue)").font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                Text("Check your internet connection and try again.").font(.deck(14)).foregroundStyle(Theme.textFaint)
                Button { reload() } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.deck(16, .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(Capsule().fill(Theme.accent.opacity(0.16)))
                }
                .buttonStyle(.pressable)
            }
        }
    }
}
