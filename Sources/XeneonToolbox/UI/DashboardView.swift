import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var weather: WeatherService

    enum DetailKind { case cpu, gpu, network }
    @State private var detailKind: DetailKind?

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
                    MetricDetailView(detail: detail(for: kind)) { close() }
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: detailKind)
    }

    private func open(_ kind: DetailKind) { detailKind = kind }
    private func close() { detailKind = nil }

    private func detail(for kind: DetailKind) -> MetricDetail {
        switch kind {
        case .cpu:
            return MetricDetail(title: "Processor", icon: "cpu.fill", color: Theme.cpu,
                                history: metrics.cpuHistory, asPercent: true)
        case .gpu:
            return MetricDetail(title: "Graphics", icon: "cube.transparent.fill", color: Theme.gpu,
                                history: metrics.gpuHistory, asPercent: true)
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
