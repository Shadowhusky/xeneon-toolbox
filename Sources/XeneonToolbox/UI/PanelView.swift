import SwiftUI

struct RootView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        HStack(spacing: 0) {
            NavRail(route: $model.route, touchOn: model.touchOn)
            ZStack {
                DeckBackground()
                content
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .dashboard: DashboardView(model: model, metrics: metrics)
        case .clock: ClockAppView()
        case .games: GamesView()
        case .chat: ChatView()
        }
    }
}

struct NavRail: View {
    @Binding var route: AppRoute
    var touchOn: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 26).padding(.bottom, 6)

            ForEach(AppRoute.allCases) { r in
                NavButton(route: r, selected: route == r) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { route = r }
                }
            }
            Spacer()
            Label(touchOn ? "Touch on" : "Touch off", systemImage: touchOn ? "hand.tap.fill" : "hand.tap")
                .labelStyle(.iconOnly)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(touchOn ? Theme.battery : Theme.textFaint)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 64, height: 56)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 22)
        }
        .frame(width: 156)
        .frame(maxHeight: .infinity)
        .background(Theme.backgroundEdge)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.stroke).frame(width: 1)
        }
    }
}

private struct NavButton: View {
    let route: AppRoute
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: route.icon)
                    .font(.system(size: 34, weight: .semibold))
                Text(route.title).font(.deck(13, .semibold)).tracking(0.3)
            }
            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
            .frame(width: 124, height: 104)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.18) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DeckBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Theme.backgroundEdge],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(0.08), .clear],
                           center: .init(x: 0.5, y: -0.1), startRadius: 10, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}
