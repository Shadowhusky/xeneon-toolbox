import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var weather: WeatherService
    @ObservedObject var layout: DashboardLayout

    enum DetailKind { case cpu, gpu, memory, network }
    @State private var detailKind: DetailKind?
    @State private var procs: [ProcRow] = []
    @State private var sampleTask: Task<Void, Never>?

    // Edit mode (reorder / hide).
    @State private var editing = false
    @State private var dragging: DashTile?
    @State private var dragFingerX: CGFloat = 0
    @State private var dragGrabDX: CGFloat = 0   // where on the tile the finger grabbed, vs its center
    @State private var frames: [DashTile: CGRect] = [:]
    private let space = "dashboard"

    var body: some View {
        let snap = metrics.snap
        ZStack {
            VStack(spacing: 14) {
                tilesRow(snap)
                    .frame(maxHeight: .infinity)
                if showBottomBar { bottomBar }
            }
            .animation(.easeInOut(duration: 0.3), value: model.media.nowPlaying == nil)
            .animation(.easeInOut(duration: 0.25), value: editing)
            .animation(.easeInOut(duration: 0.25), value: model.showNowPlaying)

            if let kind = detailKind, !editing {
                ZStack {
                    Color.black.opacity(0.62).ignoresSafeArea().onTapGesture { close() }
                    MetricDetailView(detail: detail(for: kind), processes: procs) { close() }
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: detailKind)
        .onAppear {
            switch ProcessInfo.processInfo.environment["XENEON_DETAIL"] {
            case "cpu": open(.cpu); case "gpu": open(.gpu)
            case "memory": open(.memory); case "network": open(.network)
            default: break
            }
            if ProcessInfo.processInfo.environment["XENEON_EDIT"] != nil { editing = true }
        }
        .onDisappear { close(); editing = false }
    }

    // MARK: - Tiles

    private func tilesRow(_ snap: MetricsSnapshot) -> some View {
        HStack(spacing: Theme.tileGap) {
            ForEach(layout.visible) { tile in
                tileSlot(tile, snap)
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(TileFrameKey.self) { frames = $0 }
        .overlay { floatingDragged(snap) }
        .contentShape(Rectangle())
        .gesture(reorderGesture, including: editing ? .all : .subviews)
    }

    /// The lifted copy of the tile being dragged, drawn at the finger so it never
    /// depends on the (lagging) layout frame of the reordering tile underneath.
    @ViewBuilder private func floatingDragged(_ snap: MetricsSnapshot) -> some View {
        if let d = dragging, let f = frames[d] {
            tileContent(d, snap)
                .frame(width: f.width, height: f.height)
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .scaleEffect(1.04)
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
                .position(x: dragFingerX - dragGrabDX, y: f.midY)
                .allowsHitTesting(false)
        }
    }

    private func tileSlot(_ tile: DashTile, _ snap: MetricsSnapshot) -> some View {
        let isDragging = dragging == tile
        return Group {
            if editing {
                tileContent(tile, snap).allowsHitTesting(false)
            } else if let kind = expandKind(tile) {
                tileContent(tile, snap).expandable { open(kind) }
            } else {
                tileContent(tile, snap)
            }
        }
        .background(GeometryReader { p in
            Color.clear.preference(key: TileFrameKey.self, value: [tile: p.frame(in: .named(space))])
        })
        .overlay(alignment: .topTrailing) { if editing && !isDragging { hideBadge(tile) } }
        .overlay {
            if editing && !isDragging {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
        }
        // While dragging, the in-flow tile is an invisible placeholder that still
        // holds (and reorders) its slot; the visible copy floats in the overlay.
        .opacity(isDragging ? 0 : 1)
    }

    @ViewBuilder private func tileContent(_ tile: DashTile, _ snap: MetricsSnapshot) -> some View {
        switch tile {
        case .clock: ClockTile(uptime: snap.uptime, weather: weather.weather)
        case .cpu: CPUTile(value: snap.cpu, history: metrics.cpuHistory)
        case .gpu: GPUTile(value: snap.gpu, history: metrics.gpuHistory)
        case .memory: MemoryTile(snap: snap)
        case .network: NetworkTile(snap: snap, rxHistory: metrics.netRxHistory, txHistory: metrics.netTxHistory)
        case .storage: StorageTile(snap: snap)
        case .power: PowerTile(battery: snap.battery, uptime: snap.uptime)
        case .controls: ControlsTile(status: model.touchStatus, toggleTouch: model.toggleTouch,
                                     flipX: $model.flipX, flipY: $model.flipY, swapXY: $model.swapXY,
                                     onEditLayout: { withAnimation(.easeInOut(duration: 0.25)) { close(); editing = true } },
                                     nowPlayingHidden: !model.showNowPlaying,
                                     onShowNowPlaying: { withAnimation(.easeInOut(duration: 0.25)) { model.showNowPlaying = true } })
                .frame(maxWidth: 300)
        }
    }

    private func expandKind(_ tile: DashTile) -> DetailKind? {
        switch tile {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .network: return .network
        default: return nil
        }
    }

    private func hideBadge(_ tile: DashTile) -> some View {
        Button { withAnimation(.spring(response: 0.3)) { layout.hide(tile) } } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white, Theme.batteryLow)
                .padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Reorder gesture

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
            .onChanged { v in
                if dragging == nil {
                    guard let d = frames.first(where: { $0.value.contains(v.startLocation) })?.key else { return }
                    dragging = d
                    dragGrabDX = v.startLocation.x - (frames[d]?.midX ?? v.startLocation.x)
                }
                guard let d = dragging else { return }
                dragFingerX = v.location.x
                let center = v.location.x - dragGrabDX   // the dragged tile's center under the finger
                guard let target = layout.visible.first(where: { t in
                    guard t != d, let f = frames[t] else { return false }
                    return center >= f.minX && center <= f.maxX
                }), let tf = frames[target] else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    layout.move(d, toward: target, before: center < tf.midX)
                }
            }
            .onEnded { _ in
                dragging = nil
                layout.save()
            }
    }

    // MARK: - Bottom bar (now-playing / hidden-tile tray, plus the Edit·Done control)

    /// The bottom strip is reserved only when there's something to show — while
    /// editing, or when the player bar is visible. Hidden player = no wasted space.
    private var showBottomBar: Bool {
        editing || (model.showNowPlaying && model.media.available && model.media.nowPlaying != nil)
    }

    @ViewBuilder private var bottomBar: some View {
        if editing {
            HStack(spacing: 12) {
                hiddenTrayContent.frame(maxWidth: .infinity, alignment: .leading)
                resetButton
                doneButton
            }
            .frame(minHeight: 54)
        } else {
            NowPlayingBar(media: model.media, compact: true, onHide: { model.showNowPlaying = false })
        }
    }

    @ViewBuilder private var hiddenTrayContent: some View {
        let hidden = layout.order.filter { layout.isHidden($0) }
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            if hidden.isEmpty {
                Text("Drag a tile to reorder · tap ⊖ to hide").font(.deck(13, .medium)).foregroundStyle(Theme.textFaint)
            } else {
                Text("Hidden").font(.deck(12, .bold)).tracking(1).foregroundStyle(Theme.textFaint)
                ForEach(hidden) { tile in
                    Button { withAnimation(.spring(response: 0.3)) { layout.show(tile) } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tile.icon).font(.system(size: 12, weight: .bold))
                            Text(tile.title).font(.deck(13, .semibold))
                            Image(systemName: "plus.circle.fill").font(.system(size: 13))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).frame(height: 38)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    }.buttonStyle(.pressable)
                }
            }
        }
    }

    private var resetButton: some View {
        Button { withAnimation(.spring(response: 0.3)) { layout.reset() } } label: {
            Text("Reset").font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16).frame(height: 54)
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }.buttonStyle(.pressable)
    }

    private var doneButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { layout.save(); editing = false }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                Text("Done").font(.deck(14, .semibold))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18).frame(height: 54)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Detail sampling (unchanged)

    private func open(_ kind: DetailKind) {
        detailKind = kind
        procs = []
        if kind != .network { startSampling(byMemory: kind == .memory) }
    }

    private func close() {
        detailKind = nil
        sampleTask?.cancel(); sampleTask = nil
        procs = []
    }

    private func startSampling(byMemory: Bool) {
        sampleTask?.cancel()
        sampleTask = Task { @MainActor in
            while !Task.isCancelled {
                let rows = await Task.detached(priority: .utility) {
                    ProcessSampler.sample(byMemory: byMemory, count: 14)
                }.value
                if Task.isCancelled { break }
                procs = rows
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func detail(for kind: DetailKind) -> MetricDetail {
        switch kind {
        case .cpu:
            return MetricDetail(title: "Processor", icon: "cpu.fill", color: Theme.cpu,
                                history: metrics.cpuHistory, asPercent: true, processMetric: .cpu)
        case .gpu:
            return MetricDetail(title: "Graphics", icon: "cube.transparent.fill", color: Theme.gpu,
                                history: metrics.gpuHistory, asPercent: true, processMetric: .active)
        case .memory:
            return MetricDetail(title: "Memory", icon: "memorychip.fill", color: Theme.memory,
                                history: metrics.memHistory, asPercent: true, processMetric: .mem)
        case .network:
            return MetricDetail(title: "Network · Download", icon: "dot.radiowaves.up.forward", color: Theme.netDown,
                                history: metrics.netRxHistory, asPercent: false)
        }
    }
}

private struct TileFrameKey: PreferenceKey {
    static var defaultValue: [DashTile: CGRect] = [:]
    static func reduce(value: inout [DashTile: CGRect], nextValue: () -> [DashTile: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    /// Makes a tile tappable to open its detail view, with press feedback.
    func expandable(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(.pressable)
    }
}
