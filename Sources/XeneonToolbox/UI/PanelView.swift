import SwiftUI

struct PanelView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        ZStack {
            DeckBackground()
            if model.expanded {
                ExpandedDeck(model: model, metrics: metrics)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                MinimizedBar(model: model, metrics: metrics)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

struct DeckBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Theme.backgroundEdge],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                           center: .init(x: 0.5, y: -0.1), startRadius: 10, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

struct ExpandedDeck: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        let snap = metrics.snap
        HStack(spacing: Theme.tileGap) {
            ClockTile(uptime: snap.uptime)
            CPUTile(value: snap.cpu, history: metrics.cpuHistory)
            MemoryTile(snap: snap)
            NetworkTile(snap: snap, rxHistory: metrics.netRxHistory, txHistory: metrics.netTxHistory)
            StorageTile(snap: snap)
            PowerTile(battery: snap.battery, uptime: snap.uptime)
            ControlsTile(touchOn: model.touchOn,
                         edgeDetected: model.edgeDetected,
                         toggleTouch: model.toggleTouch,
                         minimize: { model.setExpanded(false) })
                .frame(maxWidth: 320)
        }
        .padding(20)
    }
}

struct MinimizedBar: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var metrics: SystemMetrics

    var body: some View {
        let snap = metrics.snap
        VStack {
            Spacer()
            HStack(spacing: 28) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.readout(30, .bold)).foregroundStyle(Theme.textPrimary)
                }
                divider
                chip("cpu.fill", Fmt.percent(snap.cpu), Theme.cpu)
                chip("memorychip.fill", Fmt.percent(snap.memFraction), Theme.memory)
                chip("arrow.down", Fmt.rate(snap.netRx).value + Fmt.rate(snap.netRx).unit, Theme.netDown)
                if let b = snap.battery {
                    chip(b.charging ? "bolt.fill" : "battery.100", Fmt.percent(b.level),
                         b.level < 0.2 && !b.charging ? Theme.batteryLow : Theme.battery)
                }
                divider
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").foregroundStyle(model.touchOn ? Theme.accent : Theme.textFaint)
                    Text(model.touchOn ? "Touch" : "Off").font(.deck(15, .semibold))
                        .foregroundStyle(model.touchOn ? Theme.accent : Theme.textFaint)
                }
                Image(systemName: "rectangle.expand.vertical").foregroundStyle(Theme.textFaint).font(.system(size: 16, weight: .bold))
            }
            .padding(.horizontal, 30).padding(.vertical, 18)
            .background(
                Capsule().fill(Theme.tileTop.opacity(0.9))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.setExpanded(true) }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1, height: 26)
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
            Text(text).font(.readout(18, .semibold)).foregroundStyle(Theme.textPrimary)
        }
    }
}
