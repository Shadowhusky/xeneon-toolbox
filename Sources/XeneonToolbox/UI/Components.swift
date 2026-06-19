import SwiftUI

/// The layered dark surface every tile sits on.
struct TileSurface<Content: View>: View {
    var accent: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                        .fill(RadialGradient(colors: [accent.opacity(0.16), .clear],
                                             center: .top, startRadius: 0, endRadius: 260))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.25), Theme.stroke],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.top, 1)
                    .blur(radius: 0.5)
            }
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 12)
    }
}

/// Small uppercase label + glyph used as a tile header.
struct TileHeader: View {
    let title: String
    let systemImage: String
    var accent: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.deck(13, .bold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            Rectangle()
                .fill(LinearGradient(colors: [accent.opacity(0.45), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
        }
    }
}

/// Circular progress with a soft glow and hue-coded arc.
struct RingGauge<Center: View>: View {
    var value: Double               // 0...1
    var color: Color
    var lineWidth: CGFloat = 12
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color],
                                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 7)
            center
        }
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

/// Filled line ribbon for a metric history.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var fillOpacity: Double = 0.18
    var ceiling: Double? = nil   // fixed top of scale; nil = normalize to data peak

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    area(pts, in: geo.size)
                        .fill(LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    line(pts)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: color.opacity(0.6), radius: 4)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let maxV = max(ceiling ?? (values.max() ?? 1), 0.0001)
        let n = values.count
        return values.enumerated().map { i, v in
            let x = n == 1 ? size.width : size.width * CGFloat(i) / CGFloat(n - 1)
            let y = size.height * (1 - CGFloat(v / maxV))
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

/// Thin horizontal capacity bar.
struct CapacityBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * CGFloat(max(0, min(1, fraction)))))
                    .shadow(color: color.opacity(0.5), radius: 5)
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.5), value: fraction)
    }
}
