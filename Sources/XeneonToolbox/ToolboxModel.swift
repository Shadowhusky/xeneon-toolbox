import SwiftUI
import XeneonTouchDriver

/// Owns the embedded touch driver and the metrics engine. Touch works while the
/// app runs; toggling it is just start/stop on the service — no system changes.
@MainActor
final class ToolboxModel: ObservableObject {
    let metrics = SystemMetrics()
    @Published var touchOn = false
    @Published var edgeDetected = false
    @Published var expanded = true

    private let touch = TouchService(config: TouchServiceConfig(preferSeize: true))

    init() {
        if ProcessInfo.processInfo.environment["XENEON_START_MINIMIZED"] != nil {
            expanded = false
        }
        touch.onPresenceChanged = { [weak self] present in
            Task { @MainActor in self?.edgeDetected = present }
        }
    }

    func onAppear() {
        metrics.start()
        startTouch()
    }

    func startTouch() { touchOn = touch.start() }
    func stopTouch() { touch.stop(); touchOn = false }
    func toggleTouch() { touchOn ? stopTouch() : startTouch() }

    func setExpanded(_ v: Bool) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { expanded = v }
    }
}
