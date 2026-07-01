import SwiftUI

/// A macOS-Control-Centre-style panel: brightness, volume, and quick toggles —
/// pulled down from the top-right edge. All controls are sized for fingers.
struct ControlCenterView: View {
    @ObservedObject var model: ToolboxModel
    @State private var brightness: Double = 90
    @State private var volume: Double = 50
    @State private var volumeAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Controls").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)

            if model.canControlBacklight {
                FatSlider(value: $brightness, icon: "sun.max.fill", tint: Theme.netUp,
                          onEnded: { model.applyBrightness(Int($0)) })
            }
            if volumeAvailable {
                FatSlider(value: $volume, icon: "speaker.wave.2.fill", tint: Theme.accent,
                          onChanged: { SystemVolume.set(Int($0)) })
            }

            HStack(spacing: 12) {
                actionTile("Minimal", "rectangle.compress.vertical", Theme.accent) { close(); model.setDisplay(.minimal) }
                actionTile("Sleep", "moon.fill", Theme.time) { close(); model.setDisplay(.sleep) }
                actionTile("Screen off", "powersleep", Theme.netDown) { close(); model.turnScreenOff() }
            }

            touchTile

            if model.media.available, model.media.nowPlaying != nil {
                NowPlayingBar(media: model.media, compact: true)
            }
        }
        .padding(20)
        .frame(width: 760)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        .onAppear {
            brightness = Double(model.brightness)
            if let v = SystemVolume.level() { volume = Double(v); volumeAvailable = true }
        }
    }

    private func close() { model.closeControlCenter() }

    private func actionTile(_ title: String, _ icon: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                Text(title).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.pressable)
    }

    private var touchTile: some View {
        let on = model.touchStatus != .off
        return Button(action: model.toggleTouch) {
            HStack(spacing: 14) {
                Image(systemName: "hand.tap.fill").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(on ? Theme.battery : Theme.textFaint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Touch").font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(on ? "On" : "Off").font(.deck(13)).foregroundStyle(on ? Theme.battery : Theme.textFaint)
                }
                Spacer()
                ToggleDot(on: on)
            }
            .padding(.horizontal, 16).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }
}

/// A fat, drag-anywhere slider — big enough to grab on a touchscreen. The fill and
/// icon live inside the track. `onChanged` fires live (cheap side-effects like
/// volume); `onEnded` fires on release (slow ones like DDC brightness).
struct FatSlider: View {
    @Binding var value: Double   // 0…100
    var icon: String
    var tint: Color
    var onChanged: ((Double) -> Void)? = nil
    var onEnded: ((Double) -> Void)? = nil

    var body: some View {
        GeometryReader { g in
            let frac = CGFloat(min(1, max(0, value / 100)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(56, g.size.width * frac))
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .padding(.leading, 18)
                HStack {
                    Spacer()
                    Text("\(Int(value))").font(.readout(18, .bold)).foregroundStyle(.white.opacity(0.9)).padding(.trailing, 18)
                }
            }
            .frame(height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(1, max(0, v.location.x / g.size.width))
                        value = Double(f) * 100
                        onChanged?(value)
                    }
                    .onEnded { _ in onEnded?(value) }
            )
        }
        .frame(height: 58)
    }
}
