import SwiftUI
import ToolboxKit

struct RootView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @State private var ccHeight: CGFloat = 520

    var body: some View {
        Group {
            switch model.displayMode {
            case .full: fullUI
            case .minimal:
                MinimalView(metrics: metrics, todos: model.todos, media: model.media, weather: model.weather.weather,
                            showNowPlaying: model.showNowPlaying, onHideNowPlaying: { model.showNowPlaying = false })
                    .contentShape(Rectangle()).onTapGesture { model.setDisplay(.full) }
            case .sleep:
                SleepView().contentShape(Rectangle()).onTapGesture { model.setDisplay(.full) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        // Control centre lives at the top level so the top-right pull works from the
        // minimal (ambient) screen too, not just the full UI.
        .overlay { controlCenterOverlay }
        .animation(.easeInOut(duration: 0.4), value: model.displayMode)
    }

    private var fullUI: some View {
        HStack(spacing: 0) {
            if !model.fullscreen {
                NavRail(route: $model.route, touchActive: model.touchStatus == .active, todos: model.todos,
                        exportMode: model.exportMode,
                        onFullscreen: { model.toggleFullscreen() },
                        onMinimal: { model.setDisplay(.minimal) }, onSleep: { model.setDisplay(.sleep) },
                        onSettings: { model.showSettings = true })
                    .transition(.move(edge: .leading))
            }
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
                        .padding(contentInset)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.route)
        }
        .background(Theme.background)
        // In fullscreen every page hides its chrome. The exit tab sits at the
        // top-center edge — the one strip page/web/game controls (titles on the
        // left, actions on the right) reliably leave clear — so it doesn't cover
        // the underlying UI the way a top-right pill did.
        .overlay(alignment: .bottom) {
            if model.fullscreen { fullscreenControls }
        }
        .overlay {
            if model.showSettings {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { model.showSettings = false }
                    SettingsView(model: model, remote: model.remote, updater: model.updater) { model.showSettings = false }
                }
                .transition(.opacity)
            }
        }
        .overlay { UpdateGate(updater: model.updater, fullscreen: model.fullscreen) }
        // First-run coach marks for the fullscreen gestures. Sits BELOW the shade /
        // control-centre overlays so a gesture the user actually performs slides in
        // above the mask (visible), rather than being hidden behind it.
        .overlay {
            if model.showFsTutorial {
                FullscreenTutorial { model.dismissFsTutorial() }
                    .transition(.opacity)
            }
        }
        // The minimal screen being dragged in from the top (or out toward the
        // bottom) — its bottom edge tracks the finger.
        .overlay {
            if let frac = model.pullFrac { minimalPullOverlay(CGFloat(frac)) }
        }
        .animation(.easeInOut(duration: 0.3), value: model.fullscreen)
        .animation(.easeInOut(duration: 0.25), value: model.showSettings)
        .animation(.easeInOut(duration: 0.3), value: model.showFsTutorial)
    }

    @ViewBuilder private var controlCenterOverlay: some View {
        if model.controlExt > 0.001 {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.5 * model.controlExt).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeControlCenter() }
                ControlCenterView(model: model)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: CCHeightKey.self, value: g.size.height)
                    })
                    .padding(.top, 14).padding(.trailing, 18)
                    .offset(y: -(ccHeight + 30) * (1 - model.controlExt))
            }
            .onPreferenceChange(CCHeightKey.self) { ccHeight = $0 }
        }
    }

    @ViewBuilder private func minimalPullOverlay(_ frac: CGFloat) -> some View {
        GeometryReader { geo in
            MinimalView(metrics: metrics, todos: model.todos, media: model.media, weather: model.weather.weather,
                        showNowPlaying: model.showNowPlaying, onHideNowPlaying: { model.showNowPlaying = false })
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color.black)
                .overlay(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.45)).frame(width: 120, height: 5).padding(.bottom, 9)
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                .offset(y: -geo.size.height * (1 - frac))
        }
        .ignoresSafeArea()
        .transition(.move(edge: .top))
        .zIndex(60)
    }

    // Web and Games hide their own chrome and fill the panel, so they go fully
    // edge-to-edge in fullscreen. Other pages keep a small inset so their controls
    // never sit flush against the physical screen edge.
    private var contentInset: CGFloat {
        guard model.fullscreen else { return 20 }
        return (model.route == .web || model.route == .games) ? 0 : 14
    }

    // A subtle home-indicator-style handle — tap to exit (the safe fallback for the
    // swipe-up gesture). The first-run tutorial teaches the gestures themselves.
    private var fullscreenControls: some View {
        Button { model.toggleFullscreen() } label: {
            Capsule().fill(Color.white.opacity(0.35))
                .frame(width: 132, height: 5)
                .padding(.vertical, 9).padding(.horizontal, 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .dashboard: DashboardView(model: model, metrics: metrics, weather: model.weather, layout: model.dashboardLayout)
        case .deck: DeckView(model: model, deck: model.deck)
        case .clock: ClockAppView(store: model.worldClocks, exportMode: model.exportMode)
        case .tasks: TasksView(todos: model.todos, exportMode: model.exportMode)
        case .games: GamesView(model: model)
        case .web: BrowserView(model: model, store: model.webApps, web: model.web)
        case .chat: ChatView(model: model)
        }
    }
}

struct NavRail: View {
    @Binding var route: AppRoute
    var touchActive: Bool
    @ObservedObject var todos: TodoStore
    var exportMode = false
    var onFullscreen: () -> Void = {}
    var onMinimal: () -> Void = {}
    var onSleep: () -> Void = {}
    var onSettings: () -> Void = {}

    private var openTasks: Int { todos.items.filter { !$0.done }.count }
    private var hasOverdue: Bool { todos.items.contains { $0.isOverdue } }

    @ViewBuilder private var navButtons: some View {
        VStack(spacing: 7) {
            ForEach(AppRoute.allCases) { r in
                NavButton(route: r, selected: route == r,
                          badge: r == .tasks ? openTasks : 0,
                          badgeUrgent: r == .tasks && hasOverdue) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { route = r }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
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
            VStack(spacing: 9) {
                Rectangle().fill(LinearGradient(colors: [.clear, Theme.stroke], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1).padding(.horizontal, 18).padding(.bottom, 2)
                HStack(spacing: 7) {
                    Image(systemName: touchActive ? "hand.tap.fill" : "hand.tap")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(touchActive ? Theme.battery : Theme.textFaint)
                    Text(touchActive ? "Touch on" : "Touch off")
                        .font(.deck(11, .semibold)).foregroundStyle(touchActive ? Theme.battery : Theme.textFaint)
                }
                HStack(spacing: 9) {
                    railTile("Full screen", "arrow.up.left.and.arrow.down.right", Theme.accent, action: onFullscreen)
                    railTile("Minimal", "rectangle.compress.vertical", Theme.accent, action: onMinimal)
                }
                HStack(spacing: 9) {
                    railTile("Sleep", "moon.fill", Theme.time, action: onSleep)
                    railTile("Settings", "gearshape.fill", Theme.textSecondary, action: onSettings)
                }
                Button { NSApplication.shared.terminate(nil) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power").font(.system(size: 12, weight: .bold))
                        Text("Quit").font(.deck(11, .semibold))
                    }
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 14)
        }
        .frame(width: 172)
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

    private func railTile(_ label: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                Text(label).font(.deck(10.5, .semibold)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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
            HStack(spacing: 12) {
                Image(systemName: route.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 26)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.readout(10, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(badgeUrgent ? Theme.batteryLow : accent))
                                .offset(x: 13, y: -9)
                        }
                    }
                Text(route.title).font(.deck(15, .semibold)).tracking(0.2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? accent : Theme.textSecondary)
            .shadow(color: selected ? accent.opacity(0.5) : .clear, radius: 8)
            .padding(.horizontal, 15)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected
                          ? LinearGradient(colors: [accent.opacity(0.26), accent.opacity(0.10)],
                                           startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.white.opacity(0.05), .clear], startPoint: .leading, endPoint: .trailing))
            )
            .overlay(alignment: .leading) {
                Capsule().fill(accent)
                    .frame(width: 3.5, height: selected ? 28 : 0)
                    .deckGlow(accent, strength: 0.9)
                    .offset(x: 3)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

private struct CCHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 520
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
