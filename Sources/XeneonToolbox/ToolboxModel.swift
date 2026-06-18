import SwiftUI
import XeneonTouchDriver

enum AppRoute: String, CaseIterable, Identifiable {
    case dashboard, clock, games, chat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .clock: return "Clock"
        case .games: return "Games"
        case .chat: return "Assistant"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .clock: return "clock.fill"
        case .games: return "gamecontroller.fill"
        case .chat: return "sparkles"
        }
    }
}

/// Owns the embedded touch driver, the metrics engine, and app navigation.
/// Touch works while the app runs; toggling it is just start/stop — no system
/// changes.
@MainActor
final class ToolboxModel: ObservableObject {
    let metrics = SystemMetrics()
    @Published var route: AppRoute = .dashboard
    @Published var touchOn = false
    @Published var edgeDetected = false

    private let touch = TouchService(config: TouchServiceConfig(preferSeize: true))

    init() {
        if let r = ProcessInfo.processInfo.environment["XENEON_ROUTE"],
           let route = AppRoute(rawValue: r) {
            self.route = route
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
}
