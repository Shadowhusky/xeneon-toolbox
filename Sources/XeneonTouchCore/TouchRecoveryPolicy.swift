import Foundation

/// The watchdog's decision: should the app tear down and reacquire the digitizer
/// this tick? Pure so the ordering is testable — the 2026-07-11 "touch dead until
/// wake" bug was exactly a wrong ordering here: the manager-level `seized` flag
/// (which stays stale-true after the device vanishes) was checked before device
/// presence, so a lost digitizer read as "healthy" and recovery never ran.
public enum TouchRecoveryPolicy {
    /// Seize-upgrade attempts made back-to-back before backing off.
    public static let fastRetries = 5
    /// After the fast budget, retry every this many watchdog ticks (≈ 1 minute
    /// at the 6 s tick) — forever. A permanent stop is what left the panel acting
    /// as a trackpad until the user re-toggled touch.
    public static let slowRetryEvery = 10

    /// - Parameters:
    ///   - touchOn: the user wants touch running.
    ///   - deviceDetected: the digitizer is currently delivering/matched.
    ///   - displayPresent: the Edge display is active. The panel powers its touch
    ///     controller down with the display, so a missing digitizer while the
    ///     display is also gone is just panel sleep — reacquiring is futile.
    ///   - seized: we hold the device exclusively (manager-level; may be stale
    ///     when the device is gone — which is why presence is checked first).
    ///   - seizeRetries: seize-upgrade attempts so far (present-but-not-seized).
    ///   - ticksSinceRetry: watchdog ticks since the last seize attempt.
    public static func shouldReacquire(touchOn: Bool, deviceDetected: Bool, displayPresent: Bool,
                                       seized: Bool, seizeRetries: Int, ticksSinceRetry: Int) -> Bool {
        guard touchOn else { return false }
        // Device presence FIRST: a lost device reacquires whenever the display is
        // up (forever — it may be replugged at any time), no matter what the
        // stale-prone `seized` flag claims. Display also gone = panel asleep;
        // wait for the display-change notification instead of churning.
        guard deviceDetected else { return displayPresent }
        // Present but macOS also drives it as a trackpad: retry the exclusive
        // seize quickly a few times, then keep trying on a slow cadence.
        return !seized && (seizeRetries < fastRetries || ticksSinceRetry >= slowRetryEvery)
    }
}
