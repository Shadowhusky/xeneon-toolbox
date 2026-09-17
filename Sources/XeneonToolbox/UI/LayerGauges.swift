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

/// The ring arc as Core Animation layers. Animating `strokeEnd` there is
/// interpolated by the render server; animating a SwiftUI shape's `trim`
/// instead re-laid-out the entire panel on every frame of every tick, which was
/// most of the dashboard's CPU.
struct RingLayerView: NSViewRepresentable {
    var value: Double
    var color: Color
    var lineWidth: CGFloat

    func makeNSView(context: Context) -> RingHostView {
        let v = RingHostView()
        v.apply(value: value, color: NSColor(color), lineWidth: lineWidth, animated: false)
        return v
    }

    func updateNSView(_ v: RingHostView, context: Context) {
        v.apply(value: value, color: NSColor(color), lineWidth: lineWidth, animated: true)
    }
}

final class RingHostView: NSView {
    private let track = CAShapeLayer()
    private let halo = CAShapeLayer()
    private let arcMask = CAShapeLayer()
    private let arcGradient = CAGradientLayer()
    private var lineWidth: CGFloat = 12
    private var lastSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [track, halo, arcMask] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.strokeStart = 0
        }
        arcGradient.startPoint = CGPoint(x: 0.5, y: 0)
        arcGradient.endPoint = CGPoint(x: 0.5, y: 1)
        arcGradient.mask = arcMask
        layer?.addSublayer(track)
        layer?.addSublayer(halo)
        layer?.addSublayer(arcGradient)
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
        for l in [track, halo, arcMask, arcGradient] { l.contentsScale = s }
    }

    override func layout() {
        super.layout()
        if bounds.size != lastSize { lastSize = bounds.size; rebuildPaths() }
    }

    private func rebuildPaths() {
        let b = bounds
        let side = min(b.width, b.height)
        let center = CGPoint(x: b.midX, y: b.midY)
        // Room for the halo (5 pt each side of the ring) inside the frame.
        let radius = max(1, side / 2 - lineWidth / 2 - 5)
        // Start at 12 o'clock, run clockwise (the view is flipped, so angles
        // increase clockwise on screen).
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        for shape in [track, halo, arcMask] {
            shape.frame = b
            shape.path = path
        }
        arcGradient.frame = b
        track.lineWidth = lineWidth
        halo.lineWidth = lineWidth + 10
        arcMask.lineWidth = lineWidth
    }

    func apply(value: Double, color: NSColor, lineWidth: CGFloat, animated: Bool) {
        if self.lineWidth != lineWidth { self.lineWidth = lineWidth; rebuildPaths() }
        let end = CGFloat(max(0.001, min(1, value)))
        track.strokeColor = NSColor.white.withAlphaComponent(0.07).cgColor
        halo.strokeColor = color.withAlphaComponent(0.18).cgColor
        arcMask.strokeColor = NSColor.black.cgColor
        arcGradient.colors = [color.cgColor, color.withAlphaComponent(0.6).cgColor]
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        halo.strokeEnd = end
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
