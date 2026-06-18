import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics
    @ObservedObject var weather: WeatherService

    var body: some View {
        let snap = metrics.snap
        HStack(spacing: Theme.tileGap) {
            ClockTile(uptime: snap.uptime, weather: weather.weather)
            CPUTile(value: snap.cpu, history: metrics.cpuHistory)
            MemoryTile(snap: snap)
            NetworkTile(snap: snap, rxHistory: metrics.netRxHistory, txHistory: metrics.netTxHistory)
            StorageTile(snap: snap)
            PowerTile(battery: snap.battery, uptime: snap.uptime)
            ControlsTile(status: model.touchStatus, toggleTouch: model.toggleTouch,
                         flipX: $model.flipX, flipY: $model.flipY, swapXY: $model.swapXY)
                .frame(maxWidth: 300)
        }
    }
}
