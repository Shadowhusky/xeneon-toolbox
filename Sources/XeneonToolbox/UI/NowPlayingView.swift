import SwiftUI

/// A now-playing strip: artwork, track/artist, a live progress line, and
/// prev / play-pause / next transport controls. Driven by MediaController, which
/// reads and controls whatever is playing in Spotify or Music. `compact` is the
/// slimmer variant used as a floating bar in full mode; the full variant is the
/// idle/minimal screen's media card.
struct NowPlayingBar: View {
    @ObservedObject var media: MediaController
    var compact = false
    var onHide: (() -> Void)? = nil

    var body: some View {
        if media.available, let np = media.nowPlaying {
            bar(np).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func bar(_ np: NowPlaying) -> some View {
        HStack(spacing: compact ? 14 : 18) {
            artwork(np)
            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                Text(np.title).font(.deck(compact ? 16 : 20, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(np.artist.isEmpty ? np.album : np.artist)
                    .font(.deck(compact ? 12 : 14, .medium)).foregroundStyle(Theme.textFaint).lineLimit(1)
                ScrubBar(np: np, compact: compact) { media.seek(to: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            transport(np)
            if let onHide {
                Button(action: onHide) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: compact ? 12 : 14, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                        .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, compact ? 16 : 22).padding(.vertical, compact ? 8 : 14)
        .background(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(compact ? 0.4 : 0), radius: 18, y: 6)
    }

    private func artwork(_ np: NowPlaying) -> some View {
        let side: CGFloat = compact ? 44 : 64
        return Group {
            if let art = np.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.accent.opacity(0.5), Theme.disk.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: side * 0.4, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private func transport(_ np: NowPlaying) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            circle("backward.fill", size: compact ? 14 : 18, diameter: compact ? 38 : 46) { media.previous() }
            circle(np.isPlaying ? "pause.fill" : "play.fill", size: compact ? 16 : 22, diameter: compact ? 46 : 58, filled: true) { media.togglePlayPause() }
            circle("forward.fill", size: compact ? 14 : 18, diameter: compact ? 38 : 46) { media.next() }
        }
    }

    private func circle(_ icon: String, size: CGFloat, diameter: CGFloat, filled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(filled ? Color.black : Theme.textPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(filled ? AnyShapeStyle(Theme.textPrimary) : AnyShapeStyle(Color.white.opacity(0.10))))
                .overlay(Circle().strokeBorder(.white.opacity(filled ? 0 : 0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A seekable progress line: tap anywhere to jump, or drag the knob to scrub.
/// The hit area is much taller than the visible bar so it's easy to grab.
private struct ScrubBar: View {
    let np: NowPlaying
    let compact: Bool
    let onSeek: (Double) -> Void
    @State private var dragFrac: Double?

    private var knob: CGFloat { compact ? 11 : 14 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let liveFrac = np.duration > 0 ? min(1, max(0, np.elapsedNow(ctx.date) / np.duration)) : 0
            let frac = dragFrac ?? liveFrac
            let shown = dragFrac.map { $0 * np.duration } ?? np.elapsedNow(ctx.date)
            HStack(spacing: 10) {
                if !compact {
                    Text(NowPlayingBar.clock(shown)).font(.readout(11, .medium)).foregroundStyle(Theme.textFaint)
                        .frame(width: 38, alignment: .leading).monospacedDigit()
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                        Capsule().fill(Theme.accent).frame(width: max(2, g.size.width * frac), height: 4)
                        Circle().fill(.white)
                            .frame(width: knob, height: knob)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .offset(x: min(g.size.width - knob, max(0, g.size.width * frac - knob / 2)))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFrac = min(1, max(0, v.location.x / g.size.width)) }
                            .onEnded { v in
                                let f = min(1, max(0, v.location.x / g.size.width))
                                if np.duration > 0 { onSeek(f * np.duration) }
                                dragFrac = nil
                            }
                    )
                }
                .frame(height: compact ? 20 : 22)
                if !compact {
                    Text(np.duration > 0 ? NowPlayingBar.clock(np.duration) : "--:--")
                        .font(.readout(11, .medium)).foregroundStyle(Theme.textFaint)
                        .frame(width: 38, alignment: .trailing).monospacedDigit()
                }
            }
        }
    }
}
