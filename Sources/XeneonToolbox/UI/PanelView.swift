import SwiftUI
import ToolboxKit

struct RootView: View {
    @ObservedObject var model: ToolboxModel
    // Not observed here: every metrics tick would otherwise re-evaluate the
    // whole panel. The dashboard and ambient views observe it themselves.
    var metrics: SystemMetrics

    var body: some View {
        Group {
            if !model.edgePresent {
                NoEdgeView { NSApplication.shared.terminate(nil) }
            } else {
            switch model.displayMode {
            case .full: fullUI
            case .minimal:
                MinimalView(metrics: metrics, todos: model.todos, media: model.media, focusTimer: model.focusTimer, weather: model.weather.weather, nextEvent: model.calendar.next,
                            showNowPlaying: model.showNowPlaying, onHideNowPlaying: { model.showNowPlaying = false },
                            onOpenAgenda: { model.showAgenda = true }, onOpenNowPlaying: { model.showNowPlayingFull = true })
                    .contentShape(Rectangle()).onTapGesture { model.setDisplay(.full) }
            case .sleep:
                SleepView().contentShape(Rectangle()).onTapGesture { model.setDisplay(.full) }
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        // Control centre lives at the top level so the top-right pull works from the
        // minimal (ambient) screen too, not just the full UI.
        .overlay { ControlCenterHost(model: model, gestures: model.gestures) }
        // Today agenda is top-level so it opens over the ambient screen.
        .overlay {
            if model.showAgenda {
                AgendaView(events: model.calendar.today) { model.showAgenda = false }
            }
        }
        // Full-screen now-playing, over full UI or ambient.
        .overlay {
            if model.showNowPlayingFull, model.media.nowPlaying != nil {
                NowPlayingFullView(media: model.media) { model.showNowPlayingFull = false }
            }
        }
        // Focus session finished — a clear alert over whatever's on screen.
        .overlay { FocusDoneGate(timer: model.focusTimer) }
        // A scaled Edge mode: guide the user to the native resolution.
        .overlay {
            if let issue = model.displayIssue {
                ResolutionGuideView(issue: issue, appliedAt: model.displayFixAppliedAt, failed: model.displayFixFailed,
                                    onApply: { model.applyDisplayFix() }, onUndo: { model.undoDisplayFix() },
                                    onKeep: { model.keepDisplayFix() }, onLater: { model.dismissDisplayIssue() },
                                    onOpenSettings: { DisplayModeAdvisor.openDisplaySettings() })
            }
        }
        .animation(Motion.pop, value: model.displayIssue)
        .animation(Motion.standard, value: model.showNowPlayingFull)
        .animation(Motion.pop, value: model.showAgenda)
        .animation(.easeInOut(duration: 0.4), value: model.displayMode)
        .onChange(of: model.showAgenda) { if model.showAgenda { model.calendar.refresh() } }
    }

    private var fullUI: some View {
        HStack(spacing: 0) {
            if !model.fullscreen {
                NavRail(route: $model.route, touchStatus: model.touchStatus, todos: model.todos,
                        focusTimer: model.focusTimer, exportMode: model.exportMode,
                        onToggleTouch: { model.toggleTouch() },
                        onMenu: { model.showRailMenu = true })
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
                        .transition(pageTransition)
                        .padding(contentInset)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
            .animation(Motion.page, value: model.route)
        }
        .background(Theme.background)
        // In fullscreen every page hides its chrome. The exit tab sits at the
        // top-center edge — the one strip page/web controls (titles on the
        // left, actions on the right) reliably leave clear — so it doesn't cover
        // the underlying UI the way a top-right pill did.
        .overlay(alignment: .bottom) {
            if model.fullscreen { fullscreenControls }
        }
        .overlay {
            if model.showSettings {
                ModalScaffold(onDismiss: { model.showSettings = false }) {
                    SettingsView(model: model, remote: model.remote, updater: model.updater) { model.showSettings = false }
                }
            }
        }
        .overlay {
            if model.showBoost {
                let snap = metrics.snap
                BoostView(scanner: model.boost, memoryUsedGB: Double(snap.memUsed) / 1_073_741_824,
                          memoryTotalGB: Double(snap.memTotal) / 1_073_741_824, memoryPressure: snap.memFraction) {
                    model.showBoost = false
                }
            }
        }
        .animation(Motion.pop, value: model.showBoost)
        .overlay { if model.showRailMenu { RailMenu(model: model) { model.showRailMenu = false } } }
        .overlay(alignment: .bottom) { UpdateToasts(updater: model.updater, fullscreen: model.fullscreen) }
        .overlay { UpdateGate(updater: model.updater, fullscreen: model.fullscreen) }
        .overlay { if model.crashPrompt != nil { crashReportPrompt } }
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
        .overlay { ShadePullHost(model: model, gestures: model.gestures, metrics: metrics) }
        .animation(.easeInOut(duration: 0.3), value: model.fullscreen)
        .animation(Motion.pop, value: model.showSettings)
        .animation(Motion.pop, value: model.showRailMenu)
        .animation(.easeInOut(duration: 0.3), value: model.showFsTutorial)
        .animation(Motion.pop, value: model.crashPrompt != nil)
    }

    /// One-time prompt after a crash: open a prefilled GitHub issue with the
    /// report so any user can send it in a tap.
    private var crashReportPrompt: some View {
        ModalScaffold(onDismiss: { model.dismissCrashReport() }) {
            VStack(spacing: 14) {
                Image(systemName: "ladybug.fill").font(.system(size: 32)).foregroundStyle(Theme.batteryLow)
                Text("The app crashed last time").font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                Text("A crash report was saved. Sending it (opens a prefilled GitHub issue) helps get the bug fixed — nothing is sent without you.")
                    .font(.deck(14)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { model.dismissCrashReport() } label: {
                        Text("Not now").font(.deck(16, .semibold)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.buttonStyle(.pressable)
                    Button { model.sendCrashReport() } label: {
                        Text("Send report").font(.deck(16, .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.accent))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.buttonStyle(.pressable)
                }
            }
            .padding(26).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
        }
    }


    /// Swipes read as page turns (directional slide); tab taps cross-fade with a
    /// slight settle, which feels intentional rather than like a phantom swipe.
    private var pageTransition: AnyTransition {
        switch model.pageTransition {
        case .slideForward:
            return .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                               removal: .move(edge: .leading).combined(with: .opacity))
        case .slideBackward:
            return .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                               removal: .move(edge: .trailing).combined(with: .opacity))
        case .fade:
            return .asymmetric(insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.98)),
                               removal: .opacity)
        }
    }

    // The browser hides its own chrome and fills the panel, so it goes fully
    // edge-to-edge in fullscreen. Other pages keep a small inset so their controls
    // never sit flush against the physical screen edge.
    private var contentInset: CGFloat {
        guard model.fullscreen else { return 20 }
        return model.route == .web ? 0 : 14
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
        case .dashboard: DashboardView(model: model, metrics: metrics, weather: model.weather, layout: model.dashboardLayout,
                                       gestures: model.gestures, commands: model.dashboardCommands)
        case .deck: DeckView(model: model, deck: model.deck, gestures: model.gestures)
        case .surfaces: SurfacesView(model: model)
        case .clock: ClockAppView(store: model.worldClocks, timer: model.focusTimer, exportMode: model.exportMode)
        case .tasks: TasksView(todos: model.todos, exportMode: model.exportMode)
        case .web: BrowserView(model: model, web: model.web)
        case .chat: ChatView(model: model)
        }
    }
}

/// A compact rail: big finger targets (88×76 pt), icon + label, one menu
/// button for everything that isn't a destination.
struct NavRail: View {
    @Binding var route: AppRoute
    var touchStatus: ToolboxModel.TouchStatus
    let todos: TodoStore
    let focusTimer: FocusTimer
    var exportMode = false
    var onToggleTouch: () -> Void = {}
    var onMenu: () -> Void = {}

    static let width: CGFloat = 112

    @ViewBuilder private var navButtons: some View {
        VStack(spacing: 6) {
            ForEach(AppRoute.tabs) { r in
                NavButton(route: r, selected: route == r, todos: todos, focusTimer: focusTimer) {
                    withAnimation(Motion.page) { route = r }
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            brandMark
            // Destinations centred in the slack, so spacing reads as deliberate.
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
            VStack(spacing: 8) {
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 20).padding(.bottom, 2)
                touchButton
                menuButton
            }
            .padding(.bottom, 14)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Theme.backgroundEdge)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.stroke).frame(width: 1)
        }
    }

    private var brandMark: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
                .deckGlow(Theme.accent, strength: 0.6)
            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 20)
        }
        .padding(.top, 18).padding(.bottom, 10)
    }

    private var touchButton: some View {
        let (tint, label): (Color, String) = {
            switch touchStatus {
            case .active: return (Theme.battery, "Touch on")
            case .searching: return (Theme.netUp, "Searching")
            case .off: return (Theme.textFaint, "Touch off")
            }
        }()
        return Button(action: onToggleTouch) {
            VStack(spacing: 5) {
                Image(systemName: touchStatus == .off ? "hand.tap" : "hand.tap.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                Text(label).font(.deck(11, .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 88, height: 56)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.wellFill))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Lamp(color: tint, on: touchStatus != .off, size: 6).padding(8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private var menuButton: some View {
        Button(action: onMenu) {
            VStack(spacing: 5) {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("More").font(.deck(11, .semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 88, height: 64)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
            .bezel(corner: 15)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

private struct NavButton: View {
    let route: AppRoute
    let selected: Bool
    let todos: TodoStore
    let focusTimer: FocusTimer
    let action: () -> Void

    private var accent: Color { route.accent }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: route.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selected ? accent : Theme.textSecondary)
                    .frame(height: 28)
                    .overlay(alignment: .topTrailing) {
                        if route == .tasks { TasksBadge(todos: todos, accent: accent) }
                        else if route == .clock { FocusDot(timer: focusTimer) }
                    }
                Text(route.title).font(.deck(12, .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: 88, height: 76)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected
                          ? LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom),
                              lineWidth: 1)
                .opacity(selected ? 1 : 0))
            // The lit index bar: the one place the rail uses the signature amber.
            .overlay(alignment: .leading) {
                Capsule().fill(Theme.accent).frame(width: 3, height: 30)
                    .deckGlow(Theme.accent, strength: 1)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

/// Leaf observers: only these re-render when the task list or timer ticks.
private struct TasksBadge: View {
    @ObservedObject var todos: TodoStore
    var accent: Color
    var body: some View {
        let open = todos.items.filter { !$0.done }.count
        if open > 0 {
            Text("\(open)")
                .font(.readout(10, .bold)).foregroundStyle(Theme.backgroundEdge)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(todos.items.contains { $0.isOverdue } ? Theme.batteryLow : accent))
                .offset(x: 14, y: -8)
        }
    }
}

private struct FocusDot: View {
    @ObservedObject var timer: FocusTimer
    var body: some View {
        if timer.running {
            Lamp(color: Theme.accent, on: true, size: 8)
                .offset(x: 10, y: -6)
        }
    }
}

private struct CCHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 520
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The control centre pulled down from the top-right. Observes only the gesture
/// state, so the 60 Hz pull doesn't re-render the panel underneath.
private struct ControlCenterHost: View {
    let model: ToolboxModel
    @ObservedObject var gestures: PanelGestures
    @State private var ccHeight: CGFloat = 520

    var body: some View {
        if gestures.controlExt > 0.001 {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.5 * gestures.controlExt).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeControlCenter() }
                ControlCenterView(model: model, toggles: model.systemToggles, audio: model.audioOutput, keepAwake: model.keepAwake)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: CCHeightKey.self, value: g.size.height)
                    })
                    .padding(.top, 14).padding(.trailing, 18)
                    .offset(y: -(ccHeight + 30) * (1 - gestures.controlExt))
            }
            .onPreferenceChange(CCHeightKey.self) { ccHeight = $0 }
        }
    }
}

/// The ambient screen following the finger during a top-edge pull.
private struct ShadePullHost: View {
    let model: ToolboxModel
    @ObservedObject var gestures: PanelGestures
    let metrics: SystemMetrics

    var body: some View {
        if let frac = gestures.pullFrac {
            GeometryReader { geo in
                MinimalView(metrics: metrics, todos: model.todos, media: model.media, focusTimer: model.focusTimer, weather: model.weather.weather, nextEvent: model.calendar.next,
                            showNowPlaying: model.showNowPlaying, onHideNowPlaying: { model.showNowPlaying = false })
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Color.black)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Color.white.opacity(0.45)).frame(width: 120, height: 5).padding(.bottom, 9)
                    }
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                    .offset(y: -geo.size.height * (1 - CGFloat(frac)))
            }
            .ignoresSafeArea()
            .transition(.move(edge: .top))
            .zIndex(60)
        }
    }
}

/// The panel's surface: near-black carbon with one soft light falling from the
/// top-left, so bezels read as lit edges instead of drawn lines.
struct DeckBackground: View {
    var body: some View {
        ZStack {
            Theme.backgroundEdge
            LinearGradient(colors: [Theme.background, Theme.backgroundEdge],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.045), .clear],
                           center: .init(x: 0.12, y: -0.2), startRadius: 0, endRadius: 1300)
            RadialGradient(colors: [Theme.accent.opacity(0.035), .clear],
                           center: .init(x: 0.5, y: 1.3), startRadius: 0, endRadius: 1100)
        }
        .ignoresSafeArea()
    }
}
