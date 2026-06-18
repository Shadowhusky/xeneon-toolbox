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
    @Published var gamePref = "shanhai"   // "shanhai" | "rhythm"

    private let touch = TouchService(config: TouchServiceConfig(preferSeize: true))
    private var retryTimer: Timer?

    /// What the touch control shows: Active (driving the panel), Searching
    /// (wants touch but hasn't acquired the digitizer yet), or Off.
    enum TouchStatus { case active, searching, off }
    var touchStatus: TouchStatus { !touchOn ? .off : (edgeDetected ? .active : .searching) }

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

    func startTouch() {
        touchOn = true
        attemptAcquire()
    }

    /// Try to open the digitizer; if it's held (e.g. by the xeneon-touch CLI) or
    /// not yet ready, keep retrying so touch comes alive once it's free.
    private func attemptAcquire() {
        guard touchOn else { return }
        if touch.start() {
            retryTimer?.invalidate(); retryTimer = nil
        } else if retryTimer == nil {
            let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.attemptAcquire() }
            }
            RunLoop.main.add(t, forMode: .common)
            retryTimer = t
        }
    }

    func stopTouch() {
        touchOn = false
        edgeDetected = false
        retryTimer?.invalidate(); retryTimer = nil
        touch.stop()
    }

    func toggleTouch() { touchOn ? stopTouch() : startTouch() }
}
