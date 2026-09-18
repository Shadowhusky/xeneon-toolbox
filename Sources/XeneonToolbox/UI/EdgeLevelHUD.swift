import SwiftUI

/// The level an edge slide is setting, drawn along the edge the finger is on:
/// volume at the bottom, the panel's brightness at the top.
struct EdgeLevelHUD: View {
    @ObservedObject var gestures: PanelGestures

    var body: some View {
        ZStack {
            if let level = gestures.edgeLevel {
                bar(level)
                    .frame(maxHeight: .infinity, alignment: level.kind == .volume ? .bottom : .top)
                    .padding(.vertical, 22)
                    .transition(.opacity.combined(with: .move(edge: level.kind == .volume ? .bottom : .top)))
            }
        }
        .animation(Motion.pop, value: gestures.edgeLevel?.kind)
        .allowsHitTesting(false)
    }

    private func bar(_ level: PanelGestures.EdgeLevel) -> some View {
        let tint = level.kind == .volume ? Theme.accent : Theme.ice
        return HStack(spacing: 16) {
            Image(systemName: icon(level)).font(.system(size: 20, weight: .bold)).foregroundStyle(tint).frame(width: 34)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.trackFill)
                    Capsule().fill(tint).frame(width: max(10, g.size.width * level.value))
                }
            }
            .frame(height: 10)
            Text("\(Int((level.value * 100).rounded()))").font(.readout(22, .semibold)).foregroundStyle(Theme.textPrimary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 24).frame(width: 900, height: 64)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Theme.tileBottom.opacity(0.85)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }

    private func icon(_ level: PanelGestures.EdgeLevel) -> String {
        switch level.kind {
        case .brightness: return "sun.max.fill"
        case .volume: return level.value == 0 ? "speaker.slash.fill" : level.value < 0.4 ? "speaker.wave.1.fill" : level.value < 0.75 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }
}
