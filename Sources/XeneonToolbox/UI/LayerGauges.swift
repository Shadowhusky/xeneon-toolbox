import SwiftUI
import AppKit
import QuartzCore

/// Set for off-screen (ImageRenderer) exports, which can't draw AppKit-backed
/// views: gauges fall back to their static SwiftUI shapes.
private struct RenderStaticKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var renderStatic: Bool {
        get { self[RenderStaticKey.self] }
        set { self[RenderStaticKey.self] = newValue }
    }
}

/// The tick ring as Core Animation layers: one path of 48 tick segments drawn
/// dark, the same path drawn in the metric hue and masked by an arc whose
/// `strokeEnd` the render server animates. Animating a SwiftUI shape instead
/// re-laid-out the entire panel on every frame of every tick.
struct RingLayerView: NSViewRepresentable {
    var value: Double
    var color: Color
    var lineWidth: CGFloat

    func makeNSView(context: Context) -> RingHostView {
        let v = RingHostView()
        v.apply(value: value, color: NSColor(color), tickLength: lineWidth, animated: false)
        return v
    }

    func updateNSView(_ v: RingHostView, context: Context) {
        v.apply(value: value, color: NSColor(color), tickLength: lineWidth, animated: true)
    }
}

final class RingHostView: NSView {
    private let unlit = CAShapeLayer()
    private let lit = CAShapeLayer()
    private let arcMask = CAShapeLayer()
    private var tickLength: CGFloat = 12
    private var lastSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [unlit, lit] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineWidth = 2.5
        }
        arcMask.fillColor = nil
        arcMask.lineCap = .butt
        arcMask.strokeColor = NSColor.black.cgColor
        arcMask.strokeStart = 0
        lit.mask = arcMask
        layer?.addSublayer(unlit)
        layer?.addSublayer(lit)
        syncScale()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    // Purely visual: taps go to the SwiftUI button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncScale()
    }

    private func syncScale() {
        let s = window?.backingScaleFactor ?? 2
        for l in [unlit, lit, arcMask] { l.contentsScale = s }
    }

    override func layout() {
        super.layout()
        if bounds.size != lastSize { lastSize = bounds.size; rebuildPaths() }
    }

    private func rebuildPaths() {
        let b = bounds.insetBy(dx: 4, dy: 4)
        let c = CGPoint(x: b.midX, y: b.midY)
        let outer = min(b.width, b.height) / 2
        let ticks = CGMutablePath()
        for i in 0..<TickRingShape.tickCount {
            let a = (TickRingShape.startAngle + TickRingShape.sweep * Double(i) / Double(TickRingShape.tickCount - 1)) * .pi / 180
            let dx = cos(a), dy = sin(a)
            ticks.move(to: CGPoint(x: c.x + dx * (outer - tickLength), y: c.y + dy * (outer - tickLength)))
            ticks.addLine(to: CGPoint(x: c.x + dx * outer, y: c.y + dy * outer))
        }
        for shape in [unlit, lit] { shape.frame = bounds; shape.path = ticks }
        // The reveal arc runs through the middle of the ticks; the view is
        // flipped, so angles increase clockwise on screen.
        let arc = CGMutablePath()
        let start = TickRingShape.startAngle * .pi / 180
        arc.addArc(center: c, radius: outer - tickLength / 2, startAngle: start,
                   endAngle: start + TickRingShape.sweep * .pi / 180, clockwise: false)
        arcMask.frame = bounds
        arcMask.path = arc
        arcMask.lineWidth = tickLength + 6
    }

    func apply(value: Double, color: NSColor, tickLength: CGFloat, animated: Bool) {
        if self.tickLength != tickLength { self.tickLength = tickLength; rebuildPaths() }
        let end = CGFloat(max(0.002, min(1, value)))
        unlit.strokeColor = NSColor.white.withAlphaComponent(0.09).cgColor
        lit.strokeColor = color.cgColor
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.4)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        arcMask.strokeEnd = end
        CATransaction.commit()
    }
}

/// A horizontal capacity bar on layers, for the same reason as the ring.
struct BarLayerView: NSViewRepresentable {
    var fraction: Double
    var color: Color

    func makeNSView(context: Context) -> BarHostView {
        let v = BarHostView()
        v.apply(fraction: fraction, color: NSColor(color), animated: false)
        return v
    }

    func updateNSView(_ v: BarHostView, context: Context) {
        v.apply(fraction: fraction, color: NSColor(color), animated: true)
    }
}

final class BarHostView: NSView {
    private let track = CAShapeLayer()
    private let fillMask = CAShapeLayer()
    private let fillGradient = CAGradientLayer()
    private let highlight = CAShapeLayer()
    private var lastSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [track, fillMask, highlight] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.strokeStart = 0
        }
        fillGradient.startPoint = CGPoint(x: 0, y: 0.5)
        fillGradient.endPoint = CGPoint(x: 1, y: 0.5)
        fillGradient.mask = fillMask
        layer?.addSublayer(track)
        layer?.addSublayer(fillGradient)
        layer?.addSublayer(highlight)
        syncScale()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncScale()
    }

    private func syncScale() {
        let s = window?.backingScaleFactor ?? 2
        for l in [track, fillMask, fillGradient, highlight] { l.contentsScale = s }
    }

    override func layout() {
        super.layout()
        if bounds.size != lastSize { lastSize = bounds.size; rebuildPaths() }
    }

    private func rebuildPaths() {
        let b = bounds
        let h = b.height
        let r = h / 2
        let line = CGMutablePath()
        line.move(to: CGPoint(x: r, y: h / 2))
        line.addLine(to: CGPoint(x: max(r, b.width - r), y: h / 2))
        for shape in [track, fillMask] {
            shape.frame = b
            shape.path = line
            shape.lineWidth = h
        }
        fillGradient.frame = b
        // A thin lit edge along the top of the fill.
        let top = CGMutablePath()
        top.move(to: CGPoint(x: r, y: 2.5))
        top.addLine(to: CGPoint(x: max(r, b.width - r), y: 2.5))
        highlight.frame = b
        highlight.path = top
        highlight.lineWidth = 2
    }

    func apply(fraction: Double, color: NSColor, animated: Bool) {
        let end = CGFloat(max(0.02, min(1, fraction)))
        track.strokeColor = NSColor.white.withAlphaComponent(0.07).cgColor
        fillMask.strokeColor = NSColor.black.cgColor
        fillGradient.colors = [color.withAlphaComponent(0.7).cgColor, color.cgColor]
        highlight.strokeColor = NSColor.white.withAlphaComponent(0.22).cgColor
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        fillMask.strokeEnd = end
        highlight.strokeEnd = end
        CATransaction.commit()
    }
}
