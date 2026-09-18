import SwiftUI

/// The layered black-glass surface every tile sits on: gradient body, a diagonal
/// sheen, and a physical bezel. The ambient shadow belongs to the surface, not
/// the content, so a changing readout never re-rasterizes the whole tile.
struct TileSurface<Content: View>: View {
    var accent: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surface)
            .bezel(corner: Theme.tileCorner, tint: accent)
    }

    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
            // A diagonal sheen, as if lit from the top-left of the room.
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.045), .clear, accent.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 10)
    }
}

/// A tile header: the metric's icon in a tinted well, a sentence-case title,
/// and room for a status element on the right.
struct TileHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    var accent: Color = Theme.accent
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, systemImage: String, accent: Color = Theme.accent,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(accent.opacity(0.14)))
            Text(title)
                .font(.deckLabel)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: 28)
    }
}

/// A tick-ring instrument: a 270° arc of fine ticks that light up with the
/// value, the way a cluster gauge does. Live, the lit ticks are a Core
/// Animation layer (`RingLayerView`); off-screen exports draw the same ticks
/// in SwiftUI.
struct RingGauge<Center: View>: View {
    var value: Double               // 0...1
    var color: Color
    var lineWidth: CGFloat = 12     // tick length
    @ViewBuilder var center: Center
    @Environment(\.renderStatic) private var renderStatic

    var body: some View {
        ZStack {
            Circle().fill(Theme.wellFill).padding(lineWidth + 12)
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1).padding(lineWidth + 12)
            if renderStatic { staticTicks } else { RingLayerView(value: value, color: color, lineWidth: lineWidth) }
            center
        }
    }

    private var staticTicks: some View {
        ZStack {
            TickRingShape(tickLength: lineWidth).stroke(Color.white.opacity(0.09), lineWidth: 2.5)
            TickRingShape(tickLength: lineWidth).stroke(color, lineWidth: 2.5)
                .mask(TickRingShape.arcMask(fraction: value, tickLength: lineWidth))
        }
        .padding(4)
    }
}

/// Geometry shared by the static and layer-backed tick rings: 48 ticks over
/// 270°, gap at the bottom.
struct TickRingShape: Shape {
    var tickLength: CGFloat = 12
    static let tickCount = 48
    static let startAngle = -225.0   // degrees, 12 o'clock = -90
    static let sweep = 270.0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for i in 0..<Self.tickCount {
            let a = (Self.startAngle + Self.sweep * Double(i) / Double(Self.tickCount - 1)) * .pi / 180
            let dx = cos(a), dy = sin(a)
            p.move(to: CGPoint(x: c.x + dx * (outer - tickLength), y: c.y + dy * (outer - tickLength)))
            p.addLine(to: CGPoint(x: c.x + dx * outer, y: c.y + dy * outer))
        }
        return p
    }

    /// The arc that reveals the lit ticks up to `fraction`.
    static func arcMask(fraction: Double, tickLength: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: max(0.002, min(1, fraction)) * (sweep / 360))
            .stroke(Color.black, style: StrokeStyle(lineWidth: tickLength + 6, lineCap: .butt))
            .rotationEffect(.degrees(startAngle))
            .padding(-3)
    }
}

/// Filled line ribbon for a metric history: a soft area, a bright line, and a
/// lamp on the latest value.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var fillOpacity: Double = 0.16
    var ceiling: Double? = nil   // fixed top of scale; nil = normalize to data peak

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack(alignment: .bottomTrailing) {
                if pts.count <= 1 {
                    // Resting state: a faint baseline so the tile never reads as an
                    // empty void before history accumulates.
                    Capsule().fill(Theme.trackFill).frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    area(pts, in: geo.size)
                        .fill(LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    line(pts)
                        .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    line(pts)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = pts.last {
                        Circle().fill(color).frame(width: 6, height: 6)
                            .position(last)
                    }
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxV = max(ceiling ?? (values.max() ?? 1), 0.0001)
        let n = values.count
        let inset: CGFloat = 4
        return values.enumerated().map { i, v in
            let x = n == 1 ? size.width - inset : inset + (size.width - 2 * inset) * CGFloat(i) / CGFloat(n - 1)
            let y = inset + (size.height - 2 * inset) * (1 - CGFloat(v / maxV))
            return CGPoint(x: x, y: y)
        }
    }

    private func line(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func area(_ pts: [CGPoint], in size: CGSize) -> Path {
        var p = line(pts)
        p.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
        p.addLine(to: CGPoint(x: pts.first!.x, y: size.height))
        p.closeSubpath()
        return p
    }
}

/// Indeterminate branded spinner — an accent arc with the lamp bloom.
struct DeckSpinner: View {
    var color: Color = Theme.accent
    var size: CGFloat = 58
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true } }
    }
}

/// "Assistant is typing" — three lamps pulsing in sequence.
struct TypingDots: View {
    var color: Color = Theme.accent
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(color).frame(width: 8, height: 8)
                    .opacity(phase == i ? 1 : 0.28)
                    .scaleEffect(phase == i ? 1.2 : 0.85)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

/// Thin horizontal capacity bar (layer-backed live, static for exports).
struct CapacityBar: View {
    var fraction: Double
    var color: Color
    @Environment(\.renderStatic) private var renderStatic

    var body: some View {
        Group {
            if renderStatic {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.trackFill)
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(max(0, min(1, fraction)))))
                            .overlay(alignment: .top) {
                                Capsule().fill(Color.white.opacity(0.22)).frame(height: 2).padding(.horizontal, 3).padding(.top, 1.5)
                            }
                    }
                }
            } else {
                BarLayerView(fraction: fraction, color: color)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Buttons and chrome shared across the app

/// The one filled button: amber, carbon text. Used for the single primary action on a screen.
struct PrimaryButton: View {
    var title: String
    var icon: String? = nil
    var tint: Color = Theme.accent
    var height: CGFloat = 52
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                Text(title).font(.deck(15, .semibold))
            }
            .foregroundStyle(Theme.backgroundEdge)
            .padding(.horizontal, 22).frame(height: height)
            .background(Capsule().fill(tint))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// The quiet button: glass with a bezel.
struct GhostButton: View {
    var title: String
    var icon: String? = nil
    var tint: Color = Theme.textPrimary
    var height: CGFloat = 52
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(.deck(15, .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 18).frame(height: height)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// A round icon-only control (close, reload, fullscreen).
struct CircleIconButton: View {
    var icon: String
    var size: CGFloat = 44
    var tint: Color = Theme.textSecondary
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
    }
}

/// The card every modal sits in: raised glass with a bezel and a deep shadow.
struct ModalCard<Content: View>: View {
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var padding: CGFloat = 26
    var corner: CGFloat = 26
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: corner)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
    }
}
