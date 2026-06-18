import SwiftUI

struct GamesView: View {
    enum Game: String, CaseIterable { case sever = "Sever", g2048 = "2048" }
    @State private var game: Game =
        ProcessInfo.processInfo.environment["XENEON_GAME"] == "2048" ? .g2048 : .sever

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Games").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                ForEach(Game.allCases, id: \.self) { g in
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { game = g } } label: {
                        Text(g.rawValue)
                            .font(.deck(18, .semibold))
                            .foregroundStyle(game == g ? Theme.accent : Theme.textSecondary)
                            .padding(.horizontal, 24).padding(.vertical, 13)
                            .background(Capsule().fill(game == g ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Group {
                switch game {
                case .sever: SeverView()
                case .g2048: Game2048View()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
