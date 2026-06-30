import SwiftUI
import ToolboxKit

struct RootView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @State private var showFsTip = false
    @State private var fsTipToken = 0

    var body: some View {
        Group {
            switch model.displayMode {
            case .full: fullUI
            case .minimal:
                MinimalView(metrics: metrics, todos: model.todos, media: model.media,
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
        .onChange(of: model.fullscreen) { _, fs in
            if fs {
                fsTipToken += 1
                let token = fsTipToken
                withAnimation { showFsTip = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if fsTipToken == token { withAnimation { showFsTip = false } }
                }
            } else {
                showFsTip = false
            }
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
        .animation(.easeInOut(duration: 0.3), value: model.fullscreen)
        .animation(.easeInOut(duration: 0.25), value: model.showSettings)
    }

    // Web and Games hide their own chrome and fill the panel, so they go fully
    // edge-to-edge in fullscreen. Other pages keep a small inset so their controls
    // never sit flush against the physical screen edge.
    private var contentInset: CGFloat {
        guard model.fullscreen else { return 20 }
        return (model.route == .web || model.route == .games) ? 0 : 14
    }

    // A subtle home-indicator-style handle (tap to exit — the safe fallback), with
    // a tip on entering fullscreen that explains the swipe-up gesture and can be
    // dismissed immediately. Replaces the old always-on "Exit Full Screen" tab.
    private var fullscreenControls: some View {
        VStack(spacing: 10) {
            if showFsTip {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                    Text("Swipe up from the bottom edge to exit").font(.deck(12, .semibold)).foregroundStyle(Theme.textPrimary)
                    Button { withAnimation { showFsTip = false } } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textFaint)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.pressable)
                }
                .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button { model.toggleFullscreen() } label: {
                Capsule().fill(Color.white.opacity(0.35))
                    .frame(width: 132, height: 5)
                    .padding(.vertical, 9).padding(.horizontal, 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.25), value: showFsTip)
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .dashboard: DashboardView(model: model, metrics: metrics, weather: model.weather, layout: model.dashboardLayout)
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
        VStack(spacing: 9) {
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
                    railIcon("arrow.up.left.and.arrow.down.right", action: onFullscreen)
                    railIcon("rectangle.compress.vertical", action: onMinimal)
                    railIcon("moon.fill", action: onSleep)
                }
                .padding(.horizontal, 12)
                HStack(spacing: 10) {
                    railIcon("gearshape.fill", action: onSettings)
                    railIcon("power") { NSApplication.shared.terminate(nil) }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 10).padding(.bottom, 16)
        }
        .frame(width: 168)
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

    private func railIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
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
            VStack(spacing: 7) {
                Image(systemName: route.icon)
                    .font(.system(size: 25, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.readout(11, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(badgeUrgent ? Theme.batteryLow : accent))
                                .offset(x: 16, y: -8)
                        }
                    }
                Text(route.title).font(.deck(12, .semibold)).tracking(0.3)
            }
            .foregroundStyle(selected ? accent : Theme.textSecondary)
            .shadow(color: selected ? accent.opacity(0.6) : .clear, radius: 10)
            .frame(width: 132, height: 66)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected
                          ? LinearGradient(colors: [accent.opacity(0.26), accent.opacity(0.10)],
                                           startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
            )
            .overlay(alignment: .leading) {
                Capsule().fill(accent)
                    .frame(width: 4, height: selected ? 40 : 0)
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
