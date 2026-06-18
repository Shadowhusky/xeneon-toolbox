import SwiftUI

struct GamesView: View {
    enum Game: String, CaseIterable { case rhythm = "Rhythm Plus", sever = "Sever" }
    @State private var game: Game = .rhythm

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Games").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                ForEach(Game.allCases, id: \.self) { g in
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { game = g } } label: {
                        Text(g.rawValue)
                            .font(.deck(18, .semibold))
                            .foregroundStyle(game == g ? Theme.accent : Theme.textSecondary)
                            .padding(.horizontal, 22).padding(.vertical, 13)
                            .background(Capsule().fill(game == g ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Group {
                switch game {
                case .rhythm: RhythmView()
                case .sever: SeverView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
