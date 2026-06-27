import SwiftUI
import ToolboxKit

struct RootView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        Group {
            switch model.displayMode {
            case .full: fullUI
            case .minimal:
                MinimalView(metrics: metrics, todos: model.todos).contentShape(Rectangle()).onTapGesture { model.setDisplay(.full) }
            case .sleep:
                SleepView().contentShape(Rectangle()).onTapGesture { model.setDisplay(.full) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: model.displayMode)
    }

    private var fullUI: some View {
        HStack(spacing: 0) {
            NavRail(route: $model.route, touchActive: model.touchStatus == .active, todos: model.todos,
                    exportMode: model.exportMode,
                    onMinimal: { model.setDisplay(.minimal) }, onSleep: { model.setDisplay(.sleep) },
                    onSettings: { model.showSettings = true })
            ZStack(alignment: .top) {
                DeckBackground()
                // VStack lays out strictly top-down, so oversized content (e.g. a
                // long Tasks list in the off-screen renderer) anchors at the top and
                // overflows/clips at the bottom — .frame(alignment:.top) centers it.
                VStack(spacing: 0) {
                    content
                        .id(model.route)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 26)),
                            removal: .opacity.combined(with: .offset(x: -26))))
                        .padding(20)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.route)
        }
        .background(Theme.background)
        .overlay {
            if model.showSettings {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { model.showSettings = false }
                    SettingsView(model: model) { model.showSettings = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.showSettings)
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .dashboard: DashboardView(model: model, metrics: metrics, weather: model.weather)
        case .clock: ClockAppView(store: model.worldClocks, exportMode: model.exportMode)
        case .tasks: TasksView(todos: model.todos, exportMode: model.exportMode)
        case .games: GamesView(model: model)
        case .chat: ChatView(model: model)
        }
    }
}

struct NavRail: View {
    @Binding var route: AppRoute
    var touchActive: Bool
    @ObservedObject var todos: TodoStore
    var exportMode = false
    var onMinimal: () -> Void = {}
    var onSleep: () -> Void = {}
    var onSettings: () -> Void = {}

    private var openTasks: Int { todos.items.filter { !$0.done }.count }
    private var hasOverdue: Bool { todos.items.contains { $0.isOverdue } }

    @ViewBuilder private var navButtons: some View {
        VStack(spacing: 12) {
            ForEach(AppRoute.allCases) { r in
                NavButton(route: r, selected: route == r,
                          badge: r == .tasks ? openTasks : 0,
                          badgeUrgent: r == .tasks && hasOverdue) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { route = r }
                }
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            brandMark

            // App buttons centered in the slack, so spacing reads as deliberate.
            // (ScrollView content doesn't lay out in the off-screen renderer, so
            // use a plain stack when exporting.)
            Group {
                if exportMode {
                    navButtons.frame(maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) { Spacer(minLength: 0); navButtons; Spacer(minLength: 0) }
                            .frame(minHeight: 0)
                    }
                    .frame(maxHeight: .infinity)
                }
            }

            // Always-visible bottom controls, set off by a hairline.
            VStack(spacing: 12) {
                Rectangle().fill(LinearGradient(colors: [.clear, Theme.stroke], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1).padding(.horizontal, 18).padding(.bottom, 4)
                HStack(spacing: 7) {
                    Image(systemName: touchActive ? "hand.tap.fill" : "hand.tap")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(touchActive ? Theme.battery : Theme.textFaint)
                    Text(touchActive ? "Touch on" : "Touch off")
                        .font(.deck(11, .semibold)).foregroundStyle(touchActive ? Theme.battery : Theme.textFaint)
                }
                HStack(spacing: 10) {
                    railIcon("rectangle.compress.vertical", action: onMinimal)
                    railIcon("moon.fill", action: onSleep)
                }
                HStack(spacing: 10) {
                    railIcon("gearshape.fill", action: onSettings)
                    railIcon("power") { NSApplication.shared.terminate(nil) }
                }
            }
            .padding(.top, 8).padding(.bottom, 18)
        }
        .frame(width: 156)
        .frame(maxHeight: .infinity)
        .background(Theme.backgroundEdge)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.stroke).frame(width: 1)
        }
    }

    private var brandMark: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.accent)
                    .deckGlow(Theme.accent, strength: 0.6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("XENEON").font(.deck(13, .bold)).tracking(2.2).foregroundStyle(Theme.textPrimary)
                    Text("TOOLBOX").font(.deck(9, .bold)).tracking(3.4).foregroundStyle(Theme.textFaint)
                }
            }
            Rectangle().fill(LinearGradient(colors: [Theme.accent.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1).padding(.horizontal, 16)
        }
        .padding(.top, 20).padding(.bottom, 14)
    }

    private func railIcon(_ name: String, width: CGFloat = 41, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: width, height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

private struct NavButton: View {
    let route: AppRoute
    let selected: Bool
    var badge: Int = 0
    var badgeUrgent: Bool = false
    let action: () -> Void

    private var accent: Color { route.accent }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: route.icon)
                    .font(.system(size: 29, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.readout(11, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(badgeUrgent ? Theme.batteryLow : accent))
                                .offset(x: 16, y: -8)
                        }
                    }
                Text(route.title).font(.deck(13, .semibold)).tracking(0.3)
            }
            .foregroundStyle(selected ? accent : Theme.textSecondary)
            .shadow(color: selected ? accent.opacity(0.6) : .clear, radius: 10)
            .frame(width: 120, height: 82)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected
                          ? LinearGradient(colors: [accent.opacity(0.26), accent.opacity(0.10)],
                                           startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
            )
            .overlay(alignment: .leading) {
                Capsule().fill(accent)
                    .frame(width: 4, height: selected ? 52 : 0)
                    .deckGlow(accent, strength: 0.9)
                    .offset(x: -15)
            }
        }
        .buttonStyle(.pressable)
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
