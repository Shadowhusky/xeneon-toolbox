import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var weather: WeatherService

    enum DetailKind { case cpu, gpu, memory, network }
    @State private var detailKind: DetailKind?
    @State private var procs: [ProcRow] = []
    @State private var sampleTask: Task<Void, Never>?

    var body: some View {
        let snap = metrics.snap
        ZStack {
            HStack(spacing: Theme.tileGap) {
                ClockTile(uptime: snap.uptime, weather: weather.weather)
                CPUTile(value: snap.cpu, history: metrics.cpuHistory)
                    .expandable { open(.cpu) }
                GPUTile(value: snap.gpu, history: metrics.gpuHistory)
                    .expandable { open(.gpu) }
                MemoryTile(snap: snap)
                    .expandable { open(.memory) }
                NetworkTile(snap: snap, rxHistory: metrics.netRxHistory, txHistory: metrics.netTxHistory)
                    .expandable { open(.network) }
                StorageTile(snap: snap)
                PowerTile(battery: snap.battery, uptime: snap.uptime)
                ControlsTile(status: model.touchStatus, toggleTouch: model.toggleTouch,
                             flipX: $model.flipX, flipY: $model.flipY, swapXY: $model.swapXY)
                    .frame(maxWidth: 300)
            }

            if let kind = detailKind {
                ZStack {
                    Color.black.opacity(0.62).ignoresSafeArea()
                        .onTapGesture { close() }
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
        }
        .onDisappear { close() }
    }

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

    /// Sample top processes off the main thread while a detail is open, refreshing
    /// every couple of seconds so the ranking stays live.
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

private extension View {
    /// Makes a tile tappable to open its detail view, with press feedback.
    func expandable(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(.pressable)
    }
}
