import SwiftUI
import ToolboxKit

struct Game2048View: View {
    @State private var game = Game2048()
    @State private var started = false

    var body: some View {
        HStack(spacing: 28) {
            board
            sidePanel.frame(maxWidth: 360)
        }
        .onAppear { if !started { newGame(); started = true } }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let gap = side * 0.03
            let cell = (side - gap * 5) / 4
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.05))
                VStack(spacing: gap) {
                    ForEach(0..<4, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<4, id: \.self) { c in
                                tile(game.grid[r][c], size: cell)
                            }
                        }
                    }
                }
                .padding(gap)
                if game.isGameOver { gameOver }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded(handleSwipe))
        }
    }

    private func tile(_ v: Int, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color(for: v))
            .frame(width: size, height: size)
            .overlay(
                Text(v == 0 ? "" : "\(v)")
                    .font(.readout(v >= 1024 ? 30 : 40, .bold))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(v <= 4 ? Theme.textSecondary : Theme.textPrimary)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: v)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("2048").font(.deck(34, .bold)).foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text("SCORE").font(.deck(12, .bold)).tracking(1.5).foregroundStyle(Theme.textFaint)
                Text("\(game.score)").font(.readout(44, .bold)).foregroundStyle(Theme.accent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
            Text("Swipe the board or use the pad. Merge matching tiles to reach 2048.")
                .font(.deck(15)).foregroundStyle(Theme.textSecondary)
            dpad
            Spacer()
            Button(action: newGame) {
                Label("New game", systemImage: "arrow.counterclockwise")
                    .font(.deck(17, .semibold)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
    }

    private var gameOver: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.6))
            VStack(spacing: 14) {
                Text("Game over").font(.deck(34, .bold)).foregroundStyle(Theme.textPrimary)
                Button(action: newGame) {
                    Text("Try again").font(.deck(18, .semibold)).foregroundStyle(Theme.background)
                        .padding(.horizontal, 28).padding(.vertical, 13)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dpad: some View {
        VStack(spacing: 10) {
            arrow(.up, "chevron.up")
            HStack(spacing: 10) {
                arrow(.left, "chevron.left")
                arrow(.down, "chevron.down")
                arrow(.right, "chevron.right")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ dir: Game2048.Move, _ icon: String) -> some View {
        Button { doMove(dir) } label: {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 76, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func doMove(_ move: Game2048.Move) {
        if game.move(move) { spawnRandom() }
    }

    private func handleSwipe(_ v: DragGesture.Value) {
        let t = v.translation
        let move: Game2048.Move = abs(t.width) > abs(t.height)
            ? (t.width > 0 ? .right : .left)
            : (t.height > 0 ? .down : .up)
        doMove(move)
    }

    private func newGame() {
        game = Game2048()
        spawnRandom(); spawnRandom()
    }

    private func spawnRandom() {
        guard let cell = game.emptyCells().randomElement() else { return }
        game.spawn(value: Int.random(in: 0..<10) == 0 ? 4 : 2, at: cell)
    }

    private func color(for v: Int) -> Color {
        switch v {
        case 0: return Color.white.opacity(0.05)
        case 2: return Theme.cpu.opacity(0.22)
        case 4: return Theme.cpu.opacity(0.34)
        case 8: return Theme.netDown.opacity(0.5)
        case 16: return Theme.netDown.opacity(0.7)
        case 32: return Theme.netUp.opacity(0.6)
        case 64: return Theme.netUp.opacity(0.85)
        case 128: return Theme.memory.opacity(0.6)
        case 256: return Theme.memory.opacity(0.8)
        case 512: return Theme.disk.opacity(0.8)
        case 1024: return Theme.battery.opacity(0.85)
        default: return Theme.accent
        }
    }
}
