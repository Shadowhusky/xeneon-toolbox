import Foundation
import IOKit.pwr_mgt

/// Prevents the Mac from sleeping while on — the "Amphetamine / Caffeine"
/// utility, as a Control Centre toggle. Uses an IOKit power assertion (no
/// subprocess); the assertion is released automatically when the app quits.
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var on = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() { set(!on) }

    func set(_ enabled: Bool) {
        guard enabled != on else { return }
        if enabled {
            var id: IOPMAssertionID = 0
            let reason = "Xeneon Toolbox — Keep Awake" as CFString
            let rc = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id)
            if rc == kIOReturnSuccess {
                assertionID = id
                on = true
                AppLog.info("power", "keep-awake ON")
            } else {
                AppLog.error("power", "keep-awake assertion failed rc=\(rc)")
            }
        } else {
            if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
            on = false
            AppLog.info("power", "keep-awake OFF")
        }
    }
}
