import SwiftUI

struct GamesView: View {
    enum Game: String, CaseIterable {
        case shanhai = "山海残卷"
        case rhythm = "Rhythm Plus"
        var url: URL {
            switch self {
            case .shanhai: return URL(string: "https://shanhai-yi.com/")!
            case .rhythm: return URL(string: "https://v2.rhythm-plus.com/")!
            }
        }
    }

    @State private var game: Game = .shanhai
    @State private var reloadID = UUID()

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
                Button { reloadID = UUID() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textSecondary).frame(width: 46, height: 46)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            WebGameView(url: game.url)
                .id("\(game.rawValue)-\(reloadID)")
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
