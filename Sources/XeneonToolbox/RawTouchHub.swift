import SwiftUI
import XeneonTouchCore

/// One finger on a `TouchCanvas`, in the canvas's own coordinates.
struct CanvasTouch: Identifiable, Equatable {
    enum Phase { case began, moved, ended }
    let id: Int
    var location: CGPoint
    var phase: Phase
}

/// Hands the driver's raw fingers to the canvases on screen. Each canvas
/// registers its window frame; the driver stops turning touches inside it into
/// pointer events and they arrive here instead, several at a time.
@MainActor
final class RawTouchHub {
    private struct Canvas {
        var frame: CGRect
        var handler: ([CanvasTouch]) -> Void
        var live: [Int: CGPoint] = [:]
    }

    private var canvases: [Int: Canvas] = [:]
    private var nextKey = 1
    /// Sends the regions to the driver.
    var apply: ([RawRegion]) -> Void = { _ in }
    /// The Edge's origin in global coordinates (the window fills the Edge).
    var origin: () -> CGPoint = { .zero }
    /// Off whenever something covers the canvases, so the overlay gets its taps.
    var enabled = true { didSet { if enabled != oldValue { push() } } }

    func newKey() -> Int { defer { nextKey += 1 }; return nextKey }

    func register(_ key: Int, frame: CGRect, handler: @escaping ([CanvasTouch]) -> Void) {
        let live = canvases[key]?.live ?? [:]
        canvases[key] = Canvas(frame: frame, handler: handler, live: live)
        push()
    }

    func unregister(_ key: Int) {
        guard canvases.removeValue(forKey: key) != nil else { return }
        push()
    }

    /// The Edge moved in the display arrangement.
    func refresh() { push() }

    func ingest(_ touches: [RawTouch]) {
        let o = origin()
        for key in Array(canvases.keys) {
            guard var canvas = canvases[key] else { continue }
            let mine = touches.filter { $0.region == key }
            var out: [CanvasTouch] = []
            var live: [Int: CGPoint] = [:]
            for t in mine {
                let p = CGPoint(x: t.point.x - o.x - canvas.frame.minX, y: t.point.y - o.y - canvas.frame.minY)
                out.append(CanvasTouch(id: t.id, location: p, phase: canvas.live[t.id] == nil ? .began : .moved))
                live[t.id] = p
            }
            for (id, p) in canvas.live where live[id] == nil { out.append(CanvasTouch(id: id, location: p, phase: .ended)) }
            guard !out.isEmpty else { continue }
            canvas.live = live
            canvases[key] = canvas
            canvas.handler(out)
        }
    }

    private func push() {
        let o = origin()
        apply(enabled ? canvases.map { key, c in
            RawRegion(id: key, x: o.x + c.frame.minX, y: o.y + c.frame.minY, width: c.frame.width, height: c.frame.height)
        } : [])
    }
}

/// A view whose touches arrive as individual fingers: chords on keys, several
/// faders at once. `onTouches` gets every finger that changed, with its phase.
/// A mouse (or the panel with the touch driver off) drives it as one finger.
struct TouchCanvas<Content: View>: View {
    let hub: RawTouchHub
    var onTouches: ([CanvasTouch]) -> Void
    @ViewBuilder var content: Content
    @State private var key: Int?
    @State private var mouseDown = false

    var body: some View {
        content
            .contentShape(Rectangle())
            .background(GeometryReader { g in
                let frame = g.frame(in: .global)
                Color.clear
                    .onAppear { register(frame) }
                    .onChange(of: frame) { register(frame) }
            })
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    onTouches([CanvasTouch(id: -1, location: v.location, phase: mouseDown ? .moved : .began)])
                    mouseDown = true
                }
                .onEnded { v in
                    onTouches([CanvasTouch(id: -1, location: v.location, phase: .ended)])
                    mouseDown = false
                })
            .onDisappear { if let key { hub.unregister(key) } }
    }

    private func register(_ frame: CGRect) {
        let k = key ?? hub.newKey()
        key = k
        hub.register(k, frame: frame, handler: onTouches)
    }
}
