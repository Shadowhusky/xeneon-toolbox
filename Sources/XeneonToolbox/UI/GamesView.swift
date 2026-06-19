import SwiftUI

struct GamesView: View {
    @ObservedObject var model: ToolboxModel
    @State private var reloadID = UUID()
    @State private var loadState: WebLoadState = .loading

    enum Game: String, CaseIterable {
        case shanhai = "山海残卷"
        case rhythm = "Rhythm Plus"
        var key: String { self == .shanhai ? "shanhai" : "rhythm" }
        var url: URL {
            switch self {
            case .shanhai: return URL(string: "https://shanhai-yi.com/")!
            case .rhythm: return URL(string: "https://v2.rhythm-plus.com/")!
            }
        }
    }

    private var selected: Game { model.gamePref == "rhythm" ? .rhythm : .shanhai }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Games").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                ForEach(Game.allCases, id: \.self) { g in
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.gamePref = g.key } } label: {
                        Text(g.rawValue)
                            .font(.deck(18, .semibold))
                            .foregroundStyle(selected == g ? Theme.accent : Theme.textSecondary)
                            .padding(.horizontal, 22).padding(.vertical, 13)
                            .background(Capsule().fill(selected == g ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.pressable)
                }
                Button { reload() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textSecondary).frame(width: 46, height: 46)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.pressable)
            }
            ZStack {
                WebGameView(url: selected.url, state: $loadState)
                    .id("\(selected.key)-\(reloadID)")
                if loadState == .loading { loadingOverlay }
                if loadState == .failed { errorOverlay }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: loadState)
        }
        .onChange(of: selected.key) { loadState = .loading }
    }

    private func reload() { loadState = .loading; reloadID = UUID() }

    private var loadingOverlay: some View {
        ZStack {
            Theme.background.opacity(0.9)
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Loading \(selected.rawValue)…").font(.deck(16, .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var errorOverlay: some View {
        ZStack {
            Theme.background.opacity(0.95)
            VStack(spacing: 18) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 44, weight: .semibold)).foregroundStyle(Theme.textFaint)
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
