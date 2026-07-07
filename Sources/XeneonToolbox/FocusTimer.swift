import AppKit
import Combine
import ToolboxKit

/// The focus/pomodoro timer, owned by the model so it keeps counting across tab
/// switches and while the panel is on other screens — unlike the old per-view
/// `@State`, which reset every time you left the Clock page. Wraps the pure,
/// tested `FocusTimerState`; drives it from a 1 Hz timer only while running.
@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var state = FocusTimerState(minutes: 25)
    /// Set true on the tick a session completes; the UI shows an alert and clears it.
    @Published var justFinished = false

    let presets = [15, 25, 45]
    private var timer: Timer?

    init() {
        // Deterministic verification hook: XENEON_FOCUS_AUTOSTART=<minutes> starts
        // a session on launch; ="done" shows the completion alert — so both the
        // countdown/tick wiring and the finished overlay can be checked headless.
        switch ProcessInfo.processInfo.environment["XENEON_FOCUS_AUTOSTART"] {
        case "done": justFinished = true
        case let v? where Int(v) != nil: state.setDuration(minutes: Int(v)!); toggle()
        default: break
        }
    }

    var running: Bool { state.running }
    var clock: String { state.clock }
    var fraction: Double { state.fraction }
    func isPreset(_ minutes: Int) -> Bool { state.total == minutes * 60 }

    func toggle() {
        state.toggle()
        state.running ? startTicking() : stopTicking()
    }

    func reset() {
        state.reset()
        stopTicking()
    }

    func setDuration(minutes: Int) {
        state.setDuration(minutes: minutes)
        stopTicking()
    }

    func dismissFinished() { justFinished = false }

    private func startTicking() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        if state.tick() {
            stopTicking()
            justFinished = true
            if let chime = NSSound(named: "Glass") { chime.play() } else { NSSound.beep() }
        }
    }
}
