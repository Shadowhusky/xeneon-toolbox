import AppKit
import SwiftUI

/// The floating badge the app collapses into when hidden (AssistiveTouch-style):
/// a small always-on-top puck on the Edge that stays out of the way, can be
/// dragged anywhere, and restores the full panel on tap — so the Edge can host
/// other apps' windows while the Toolbox waits in the corner.
@MainActor
final class BadgeController {
    private var panel: NSPanel?
    private let onTap: () -> Void
    private static let posKey = "badge.position"
    static let size: CGFloat = 56

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(on screen: NSScreen) {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        panel.setFrameOrigin(clampedOrigin(restoreOrigin(on: screen), on: screen))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Keep the badge above whatever lands on the Edge (Space switches re-insert
    /// canJoinAllSpaces windows behind their level-mates, same as the kiosk).
    func assertFront() {
        guard let panel, panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let s = Self.size
        // Non-activating, like the kiosk: tapping the badge must not steal focus
        // from whatever the user is working in.
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: s, height: s),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = AppDelegate.kioskLevel
        p.collectionBehavior = [.canJoinAllSpaces]
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true

        let drag = BadgeDragView(frame: NSRect(x: 0, y: 0, width: s, height: s))
        drag.onTap = { [weak self] in self?.onTap() }
        drag.onMoved = { origin in
            AppDefaults.shared.set(NSStringFromPoint(origin), forKey: Self.posKey)
        }
        let host = NSHostingView(rootView: BadgeFace())
        host.frame = drag.bounds
        host.autoresizingMask = [.width, .height]
        drag.addSubview(host)
        p.contentView = drag
        return p
    }

    private func restoreOrigin(on screen: NSScreen) -> NSPoint {
        if let s = AppDefaults.shared.string(forKey: Self.posKey) {
            return NSPointFromString(s)
        }
        // Default: bottom-right corner of the Edge, inset from the edges.
        let f = screen.frame
        return NSPoint(x: f.maxX - Self.size - 18, y: f.minY + 18)
    }

    private func clampedOrigin(_ o: NSPoint, on screen: NSScreen) -> NSPoint {
        let f = screen.frame
        return NSPoint(x: min(max(o.x, f.minX), f.maxX - Self.size),
                       y: min(max(o.y, f.minY), f.maxY - Self.size))
    }
}

/// Mouse handling for the badge: drag moves the panel, a press that never leaves
/// the tap slop restores the app on release. All events land here (the SwiftUI
/// face below is display-only) — which also makes it work with the touch
/// driver's injected press/drag/release stream.
private final class BadgeDragView: NSView {
    var onTap: () -> Void = {}
    var onMoved: (NSPoint) -> Void = { _ in }

    private var downAt = NSPoint.zero          // global mouse at press
    private var originAt = NSPoint.zero        // window origin at press
    private var moved = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil     // swallow subview hit-testing
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        originAt = window?.frame.origin ?? .zero
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - downAt.x, dy = now.y - downAt.y
        if abs(dx) > 4 || abs(dy) > 4 { moved = true }
        guard moved else { return }
        var o = NSPoint(x: originAt.x + dx, y: originAt.y + dy)
        if let screen = window.screen ?? NSScreen.main {
            let f = screen.frame
            o.x = min(max(o.x, f.minX), f.maxX - window.frame.width)
            o.y = min(max(o.y, f.minY), f.maxY - window.frame.height)
        }
        window.setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) {
        if moved { onMoved(window?.frame.origin ?? .zero) }
        else { onTap() }
    }

    // The touch driver classifies vertical finger moves as SCROLL (no mouse
    // drag), so without this the badge would only drag sideways by touch.
    // Scroll events route at the finger point, so while the finger is over the
    // badge its deltas land here — treat them as movement.
    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        var o = window.frame.origin
        o.x += event.scrollingDeltaX
        o.y -= event.scrollingDeltaY   // Cocoa origin is bottom-left; finger-down = badge down
        if let screen = window.screen ?? NSScreen.main {
            let f = screen.frame
            o.x = min(max(o.x, f.minX), f.maxX - window.frame.width)
            o.y = min(max(o.y, f.minY), f.maxY - window.frame.height)
        }
        window.setFrameOrigin(o)
        onMoved(o)
    }
}

/// The badge's look: the app's grid mark in a glassy cyan-rimmed puck.
private struct BadgeFace: View {
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.black.opacity(0.45))
            Circle().strokeBorder(Theme.accent.opacity(0.65), lineWidth: 1.5)
                .deckGlow(Theme.accent, strength: 0.7)
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(2)
    }
}
