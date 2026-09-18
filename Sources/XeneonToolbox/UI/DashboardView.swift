import SwiftUI

/// What other parts of the app can ask the dashboard to do (the rail menu's
/// "Edit dashboard"). Tiny, so only the board observes it.
@MainActor
final class DashboardCommands: ObservableObject {
    @Published var editing = false
}

/// The dashboard: a 2×8 grid of tiles, first-fit packed from an ordered board.
/// Edit mode reorders by dragging, removes, resizes, and adds from a gallery.
struct DashboardView: View {
    let model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var weather: WeatherService
    @ObservedObject var layout: DashboardLayout
    @ObservedObject var gestures: PanelGestures
    @ObservedObject var commands: DashboardCommands

    typealias DetailKind = MetricKind
    @State private var detailKind: DetailKind?
    @State private var showWeather = false
    @State private var showEnergy = false
    @State private var showGallery = false
    @StateObject private var power = PowerTelemetry()
    @State private var procs: [ProcRow] = []
    @State private var sampleTask: Task<Void, Never>?

    @State private var dragging: DashTile?
    @State private var dragPoint: CGPoint = .zero
    @State private var dragGrab: CGSize = .zero
    @State private var boardOrigin: CGPoint = .zero   // board origin in window coords, for the driver's long-press
    @State private var cell: CGSize = .zero
    @State private var toast: String?
    @State private var dockFrames: [String: CGRect] = [:]
    @State private var dockPicker: DeckAction?
    @State private var netInfo = NetworkInfo()
    @State private var sysDetail = SystemDetail()
    @State private var revealed = false
    @Environment(\.renderStatic) private var renderStatic

    private let gap: CGFloat = 16
    private var editing: Bool { commands.editing }

    var body: some View {
        let snap = metrics.snap
        ZStack {
            VStack(spacing: 12) {
                board(snap).frame(maxHeight: .infinity)
                if editing { editBar }
            }
            .animation(Motion.standard, value: editing)

            if let kind = detailKind, !editing {
                ModalScaffold(dim: 0.62, onDismiss: { close() }) {
                    MetricConsole(kind: kind, frame: metrics.frame, detail: sysDetail, processes: procs, network: netInfo,
                                  onBoost: { close(); model.showBoost = true }, onClose: { close() })
                }
                .zIndex(1)
            }
            if showWeather, !editing {
                ModalScaffold(dim: 0.62, onDismiss: { showWeather = false }) {
                    WeatherDetailView(service: weather) { showWeather = false }
                }
                .zIndex(1)
            }
            if showEnergy, !editing {
                ModalScaffold(dim: 0.62, onDismiss: { closeEnergy() }) {
                    EnergyFlowView(power: power, topApps: procs) { closeEnergy() }
                }
                .zIndex(1)
            }
        }
        .animation(Motion.pop, value: detailKind)
        .animation(Motion.pop, value: showWeather)
        .animation(Motion.pop, value: showEnergy)
        .overlay { if showGallery { TileGalleryOverlay(layout: layout) { showGallery = false } } }
        .overlay {
            if let a = dockPicker {
                ScreenPickerOverlay(model: model, deck: model.deck, action: a, running: true) { dockPicker = nil }
            }
        }
        .animation(Motion.pop, value: dockPicker)
        .onPreferenceChange(DockIconFrameKey.self) { dockFrames = $0 }
        .overlay(alignment: .bottom) { if let t = toast { toastView(t).padding(.bottom, editing ? 70 : 14) } }
        .animation(Motion.pop, value: showGallery)
        .animation(Motion.snappy, value: toast)
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            switch env["XENEON_DETAIL"] {
            case "cpu": open(.cpu); case "gpu": open(.gpu)
            case "memory": open(.memory); case "network": open(.network)
            default: break
            }
            if env["XENEON_ENERGY"] != nil { openEnergy() }
            if env["XENEON_DETAIL"] == "weather" { showWeather = true }
            if env["XENEON_EDIT"] != nil { commands.editing = true }
            if env["XENEON_GALLERY"] != nil { commands.editing = true; showGallery = true }
            syncDriver()
            // The off-screen renderer can't run the reveal, so it starts revealed there.
            if renderStatic { revealed = true } else { DispatchQueue.main.async { revealed = true } }
        }
        // In edit mode the driver treats any finger move as a mouse drag, so tiles
        // can be grabbed without the gesture misclassifying as a scroll; and the
        // long-press that enters edit mode is only armed while browsing.
        .onChange(of: editing) { dragging = nil; syncDriver(); if !editing { layout.save() } }
        .onChange(of: showGallery) { dragging = nil; syncDriver() }
        .onChange(of: detailKind) { syncDriver() }
        .onChange(of: showWeather) { syncDriver() }
        .onChange(of: showEnergy) { syncDriver() }
        .onChange(of: dockPicker) { syncDriver() }
        .onChange(of: gestures.longPressAt) { handleLongPress() }
        .onDisappear {
            model.setReorderDragging(false); model.setLongPressEnabled(false)
            close(); closeEnergy(); commands.editing = false
        }
    }

    // MARK: - Board

    private func board(_ snap: MetricsSnapshot) -> some View {
        GeometryReader { geo in
            let cw = (geo.size.width - CGFloat(DashboardLayout.columns - 1) * gap) / CGFloat(DashboardLayout.columns)
            let ch = (geo.size.height - CGFloat(DashboardLayout.rows - 1) * gap) / CGFloat(DashboardLayout.rows)
            let frames = tileFrames(cellW: cw, cellH: ch)
            let order = revealOrder(frames)
            ZStack(alignment: .topLeading) {
                ForEach(layout.board) { placed in
                    if let f = frames[placed.tile] {
                        tileSlot(placed, snap: snap)
                            .frame(width: f.width, height: f.height)
                            .opacity(revealed ? 1 : 0)
                            .scaleEffect(revealed ? 1 : 0.94)
                            .animation(Motion.standard.delay(Double(order[placed.tile] ?? 0) * 0.04), value: revealed)
                            .position(x: f.midX, y: f.midY)
                    }
                }
                floatingDragged(frames, snap)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(reorderGesture(frames), including: editing ? .all : .subviews)
            .onAppear { boardOrigin = geo.frame(in: .global).origin; cell = CGSize(width: cw, height: ch) }
            .onChange(of: geo.size) { boardOrigin = geo.frame(in: .global).origin; cell = CGSize(width: cw, height: ch) }
        }
    }

    /// Left-to-right sweep across the strip, top row before bottom in a column.
    private func revealOrder(_ frames: [DashTile: CGRect]) -> [DashTile: Int] {
        let sorted = frames.sorted { ($0.value.minX, $0.value.minY) < ($1.value.minX, $1.value.minY) }
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element.key, $0.offset) })
    }

    private func tileFrames(cellW: CGFloat, cellH: CGFloat) -> [DashTile: CGRect] {
        var out: [DashTile: CGRect] = [:]
        for (tile, s) in layout.slots {
            let x = CGFloat(s.column) * (cellW + gap)
            let y = CGFloat(s.row) * (cellH + gap)
            let w = CGFloat(s.columns) * cellW + CGFloat(s.columns - 1) * gap
            let h = CGFloat(s.rows) * cellH + CGFloat(s.rows - 1) * gap
            out[tile] = CGRect(x: x, y: y, width: w, height: h)
        }
        return out
    }

    @ViewBuilder private func tileSlot(_ placed: PlacedTile, snap: MetricsSnapshot) -> some View {
        let isDragging = dragging == placed.tile
        Group {
            if editing {
                tileContent(placed, snap).allowsHitTesting(false).opacity(0.72)
            } else if let action = tapAction(placed.tile) {
                tileContent(placed, snap).expandable(action)
            } else {
                tileContent(placed, snap)
            }
        }
        .overlay {
            if editing && !isDragging {
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
        }
        // Badges straddle the corners (iOS jiggle-mode style) so they cover as
        // little of the tile's own header controls as possible.
        .overlay(alignment: .topTrailing) { if editing && !isDragging { removeBadge(placed.tile).offset(x: 8, y: -8) } }
        .overlay(alignment: .bottomTrailing) { if editing && !isDragging && placed.tile.sizes.count > 1 { sizeBadge(placed).offset(x: 8, y: 8) } }
        // While dragging, the in-flow tile is an invisible placeholder that still
        // holds (and reorders) its slot; the visible copy floats in the overlay.
        .opacity(isDragging ? 0 : 1)
    }

    /// The lifted copy of the tile being dragged, drawn at the finger so it never
    /// depends on the (lagging) layout frame of the reordering tile underneath.
    @ViewBuilder private func floatingDragged(_ frames: [DashTile: CGRect], _ snap: MetricsSnapshot) -> some View {
        if let d = dragging, let placed = layout.board.first(where: { $0.tile == d }), let f = frames[d] {
            tileContent(placed, snap)
                .frame(width: f.width, height: f.height)
                .overlay(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .scaleEffect(1.04)
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
                .position(x: dragPoint.x - dragGrab.width, y: dragPoint.y - dragGrab.height)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func tileContent(_ placed: PlacedTile, _ snap: MetricsSnapshot) -> some View {
        let size = placed.size
        switch placed.tile {
        case .clock: ClockTile(uptime: Self.minutes(snap.uptime), weather: weather.weather, size: size)
        case .cpu: CPUTile(value: snap.cpu, history: metrics.cpuHistory, size: size)
        case .gpu: GPUTile(value: snap.gpu, history: metrics.gpuHistory, available: snap.gpuAvailable, size: size)
        case .memory: MemoryTile(snap: snap, history: metrics.memHistory, size: size)
        case .network: NetworkTile(snap: snap, rxHistory: metrics.netRxHistory, txHistory: metrics.netTxHistory, size: size)
        case .storage: StorageTile(snap: snap)
        case .power: PowerTile(battery: snap.battery, uptime: Self.minutes(snap.uptime), systemWatts: snap.systemWatts)
        case .upNext: UpNextTile(calendar: model.calendar, size: size)
        case .tasks: TasksTile(todos: model.todos, size: size, onOpen: { model.route = .tasks })
        case .thermals: ThermalsTile(thermals: snap.thermals)
        case .dock: DockTile(monitor: model.runningApps, size: size)
        case .clipboard: ClipboardTile(store: model.clipboard, size: size)
        case .nowPlaying: NowPlayingTile(media: model.media, size: size, onExpand: { model.showNowPlayingFull = true })
        case .focus: FocusTile(timer: model.focusTimer, onOpen: { model.route = .clock })
        case .worldClocks: WorldClocksTile(store: model.worldClocks, size: size)
        case .weather: WeatherTile(weather: weather.weather, loading: !weather.firstAttemptDone, size: size)
        case .devices: DevicesTile(devices: model.bluetooth, size: size)
        case .quickActions: QuickActionsTile(model: model, keepAwake: model.keepAwake, size: size)
        }
    }

    /// Tiles that open something when tapped as a whole. Tiles with their own
    /// controls (tasks, dock, clipboard, now playing) handle taps themselves.
    private func tapAction(_ tile: DashTile) -> (() -> Void)? {
        switch tile {
        case .clock: return { close(); showWeather = true }
        case .cpu: return { open(.cpu) }
        case .gpu: return { open(.gpu) }
        case .memory: return { open(.memory) }
        case .network: return { open(.network) }
        case .power: return { close(); openEnergy() }
        case .upNext: return { model.showAgenda = true }
        case .worldClocks: return { model.route = .clock }
        case .weather: return { close(); showWeather = true }
        default: return nil
        }
    }

    /// Uptime is shown to the minute; feeding tiles the raw seconds re-rendered
    /// them on every tick for a value that never visibly changed.
    private static func minutes(_ seconds: TimeInterval) -> TimeInterval { (seconds / 60).rounded(.down) * 60 }

    // MARK: - Edit mode

    private func removeBadge(_ tile: DashTile) -> some View {
        Button { withAnimation(Motion.standard) { layout.remove(tile) } } label: {
            Image(systemName: "minus").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.batteryLow))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable).padding(8)
    }

    private func sizeBadge(_ placed: PlacedTile) -> some View {
        Button {
            guard let next = layout.nextSize(for: placed.tile) else { return }
            let ok = withAnimation(Motion.snappy) { layout.setSize(placed.tile, next) }
            if !ok { showToast("\(next.name) doesn't fit — free up room first") }
        } label: {
            HStack(spacing: 5) {
                Text(placed.size.label).font(.readout(13, .bold))
                Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.backgroundEdge)
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(Theme.accent))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable).padding(8)
    }

    private var editBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x2").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                Text("\(layout.cellsUsed) of \(DashboardLayout.capacity) cells").font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                if !layout.overflow.isEmpty {
                    Text("\(layout.overflow.count) tile\(layout.overflow.count == 1 ? " doesn't" : "s don't") fit. Remove or shrink one.")
                        .font(.deck(13)).foregroundStyle(Theme.warning)
                } else {
                    Text("Drag to move. Tap the size to resize.").font(.deck(13)).foregroundStyle(Theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GhostButton(title: "Add tile", icon: "plus", tint: Theme.textPrimary, height: 54) { showGallery = true }
            GhostButton(title: "Reset", icon: "arrow.counterclockwise", tint: Theme.textSecondary, height: 54) {
                withAnimation(Motion.standard) { layout.reset() }
            }
            PrimaryButton(title: "Done", icon: "checkmark", height: 54) {
                withAnimation(Motion.standard) { layout.save(); commands.editing = false }
            }
        }
        .frame(minHeight: 54)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func toastView(_ text: String) -> some View {
        Text(text).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18).frame(height: 44)
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(Theme.tileBottom.opacity(0.85)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 16, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { if toast == text { toast = nil } }
    }

    private func syncDriver() {
        model.setReorderDragging(editing && !showGallery)
        model.setLongPressEnabled(!editing && !showGallery && detailKind == nil && !showWeather && !showEnergy && dockPicker == nil)
    }

    /// A driver long-press: on a running-app icon it opens the screen picker for
    /// that app; anywhere else on the board it enters edit mode.
    private func handleLongPress() {
        guard let pt = gestures.longPressAt else { return }
        gestures.longPressAt = nil
        guard !editing, !showGallery, detailKind == nil, !showWeather, !showEnergy, dockPicker == nil else { return }
        if let path = dockFrames.first(where: { $0.value.contains(pt) })?.key,
           let app = model.runningApps.apps.first(where: { $0.path == path }) {
            var action = DeckAction.app(path: app.path)
            action.label = app.name
            dockPicker = action
            return
        }
        let local = CGPoint(x: pt.x - boardOrigin.x, y: pt.y - boardOrigin.y)
        guard tileFrames(cellW: cell.width, cellH: cell.height).values.contains(where: { $0.contains(local) }) else { return }
        withAnimation(Motion.standard) { commands.editing = true }
    }

    // MARK: - Reorder gesture

    private func reorderGesture(_ frames: [DashTile: CGRect]) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if dragging == nil {
                    guard let d = frames.first(where: { $0.value.contains(v.startLocation) })?.key else { return }
                    dragging = d
                    let f = frames[d] ?? .zero
                    dragGrab = CGSize(width: v.startLocation.x - f.midX, height: v.startLocation.y - f.midY)
                }
                guard let d = dragging else { return }
                dragPoint = v.location
                let center = CGPoint(x: v.location.x - dragGrab.width, y: v.location.y - dragGrab.height)
                guard let target = frames.first(where: { $0.key != d && $0.value.contains(center) }),
                      let tf = frames[target.key] else { return }
                withAnimation(Motion.snappy) { layout.move(d, toward: target.key, before: center.x < tf.midX) }
            }
            .onEnded { _ in
                dragging = nil
                layout.save()
            }
    }

    // MARK: - Detail sampling

    private func open(_ kind: DetailKind) {
        detailKind = kind
        procs = []
        startSampling(byMemory: kind == .memory, network: kind == .network)
        if kind == .network { loadNetworkInfo() }
    }

    private func loadNetworkInfo() {
        netInfo = NetworkInfo(ssid: nil, localIP: metrics.snap.localIPv4, publicIP: nil, loading: true)
        Task {
            let (ssid, local) = await Task.detached { (SystemToggles.currentSSID(), MetricsSampler.localIPv4()) }.value
            netInfo.ssid = ssid
            netInfo.localIP = local ?? netInfo.localIP
            let ip = await PublicIP.shared.fetch()
            netInfo.publicIP = ip
            netInfo.loading = false
        }
    }

    private func close() {
        detailKind = nil
        sampleTask?.cancel(); sampleTask = nil
        procs = []
    }

    /// Energy modal: SoC watt sampling + top-CPU apps (the "high power" list).
    private func openEnergy() {
        showEnergy = true
        procs = []
        power.start()
        startSampling(byMemory: false, network: false)
    }

    private func closeEnergy() {
        showEnergy = false
        power.stop()
        sampleTask?.cancel(); sampleTask = nil
        procs = []
    }

    private func startSampling(byMemory: Bool, network: Bool) {
        sampleTask?.cancel()
        let sampler = DetailSampler()
        sampleTask = Task { @MainActor in
            while !Task.isCancelled {
                let (rows, detail) = await Task.detached(priority: .utility) {
                    (ProcessSampler.sample(byMemory: byMemory, count: 14), sampler.sample(network: network))
                }.value
                if Task.isCancelled { break }
                procs = rows
                sysDetail = detail
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

private extension View {
    /// Makes a tile tappable to open its detail view, with press feedback.
    func expandable(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(.pressable)
    }
}
