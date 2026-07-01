import SwiftUI

/// First-run coach marks for fullscreen mode. Masks the app and walks through each
/// edge gesture with a pulsing hint pointed at the relevant screen edge. Shown once
/// (the caller persists "seen"); dismissable at any step.
struct FullscreenTutorial: View {
    var onDone: () -> Void
    @State private var step = 0

    private enum Hint { case bottom, topLeft, topRight, sides }
    private struct Step { let hint: Hint; let icon: String; let title: String; let text: String }

    private let steps: [Step] = [
        .init(hint: .bottom, icon: "chevron.up", title: "Exit fullscreen",
              text: "Swipe up from the bottom edge to leave fullscreen."),
        .init(hint: .topLeft, icon: "chevron.down", title: "Minimal mode",
              text: "Swipe down from the top-left to drop to the ambient screen."),
        .init(hint: .topRight, icon: "slider.horizontal.3", title: "Control Centre",
              text: "Swipe down from the top-right for brightness, volume and quick actions."),
        .init(hint: .sides, icon: "arrow.left.and.right", title: "Switch apps",
              text: "Swipe in from the left or right edge to move between apps."),
    ]

    var body: some View {
        let s = steps[step]
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { advance() }
            hint(for: s.hint)

            VStack(spacing: 16) {
                Image(systemName: s.icon).font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.accent)
                Text(s.title).font(.deck(26, .bold)).foregroundStyle(Theme.textPrimary)
                Text(s.text).font(.deck(17)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    ForEach(steps.indices, id: \.self) { i in
                        Circle().fill(i == step ? Theme.accent : Color.white.opacity(0.22))
                            .frame(width: 7, height: 7)
                    }
                }.padding(.top, 2)

                HStack(spacing: 12) {
                    Button(action: onDone) {
                        Text("Skip").font(.deck(16, .semibold)).foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button(action: advance) {
                        Text(step == steps.count - 1 ? "Got it" : "Next")
                            .font(.deck(16, .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.accent))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.buttonStyle(.pressable)
                }.padding(.top, 4)
            }
            .padding(30)
            .frame(width: 540)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .animation(.easeInOut(duration: 0.28), value: step)
        .transition(.opacity)
        .onAppear {
            if let s = ProcessInfo.processInfo.environment["XENEON_TUT_STEP"], let i = Int(s) {
                step = min(max(0, i), steps.count - 1)
            }
        }
    }

    private func advance() {
        if step == steps.count - 1 { onDone() } else { withAnimation { step += 1 } }
    }

    @ViewBuilder private func hint(for hint: Hint) -> some View {
        switch hint {
        case .bottom:
            EdgeArrow(direction: .up).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26)
        case .topLeft:
            EdgeArrow(direction: .down).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 22).padding(.leading, 120)
        case .topRight:
            EdgeArrow(direction: .down).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 22).padding(.trailing, 120)
        case .sides:
            HStack {
                EdgeArrow(direction: .right)
                Spacer()
                EdgeArrow(direction: .left)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 36)
        }
    }
}

/// A glowing chevron that pulses toward a screen edge to point out a gesture.
private struct EdgeArrow: View {
    enum Direction { case up, down, left, right }
    let direction: Direction
    @State private var pulse = false

    private var icon: String {
        switch direction {
        case .up: return "chevron.up"; case .down: return "chevron.down"
        case .left: return "chevron.left"; case .right: return "chevron.right"
        }
    }
    private var offset: CGSize {
        let d: CGFloat = pulse ? 12 : 0
        switch direction {
        case .up: return CGSize(width: 0, height: -d)
        case .down: return CGSize(width: 0, height: d)
        case .left: return CGSize(width: -d, height: 0)
        case .right: return CGSize(width: d, height: 0)
        }
    }

    private var horizontal: Bool { direction == .left || direction == .right }

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: -8) { chevron(0.9); chevron(0.4) }
            } else {
                VStack(spacing: -10) { chevron(0.9); chevron(0.4) }
            }
        }
        .foregroundStyle(Theme.accent)
        .shadow(color: Theme.accent.opacity(0.7), radius: 12)
        .offset(offset)
        .onAppear { withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true } }
    }

    private func chevron(_ opacity: Double) -> some View {
        Image(systemName: icon).font(.system(size: 30, weight: .heavy)).opacity(opacity)
    }
}
