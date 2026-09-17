import AppKit
import XeneonTouchCore
import XeneonTouchDriver

/// A wrong Edge mode the user should know about, with what we can do about it.
struct DisplayIssue: Equatable {
    let displayID: CGDirectDisplayID
    let currentLabel: String                    // e.g. "1920 × 1080"
    let recommended: DisplayModeCandidate?      // nil → only the manual path is possible
    let previousModeNumber: Int32?              // for Undo after we switched
}

/// macOS treats 1920×1080 as the Edge's default mode, so a fresh panel comes up
/// scaled and the Toolbox can't fit the strip. Detect that, and switch to the
/// native timing on request — through the same window-server call the Displays
/// pane uses, since the public mode list hides the native mode on some Macs.
@MainActor
enum DisplayModeAdvisor {
    private static let dismissedKey = "display.guide.dismissedMode"

    /// The issue to surface, or nil: no Edge, already native, or already dismissed
    /// for this exact mode (it comes back if the mode changes again).
    static func check(ignoringDismissal: Bool = false) -> DisplayIssue? {
        if ProcessInfo.processInfo.environment["XENEON_RESOLUTION_DEMO"] != nil {
            return DisplayIssue(displayID: 0, currentLabel: "1920 × 1080",
                                recommended: DisplayModeCandidate(number: 28, width: 2560, height: 720, density: 1, flags: 0x3),
                                previousModeNumber: 26)
        }
        guard let edge = EdgeScreen.current(), !edge.isNativeMode else { return nil }
        if !ignoringDismissal, AppDefaults.shared.string(forKey: dismissedKey) == edge.modeLabel { return nil }
        let modes = CGSDisplayModes.all(for: edge.id)
        return DisplayIssue(displayID: edge.id, currentLabel: edge.modeLabel,
                            recommended: EdgeModeChooser.best(from: modes),
                            previousModeNumber: CGSDisplayModes.current(for: edge.id))
    }

    static func apply(_ issue: DisplayIssue) -> Bool {
        guard let m = issue.recommended else { return false }
        AppLog.info("display", "switching Edge to mode \(m.number) (\(m.label))")
        let ok = CGSDisplayModes.apply(m.number, to: issue.displayID)
        if !ok { AppLog.error("display", "mode switch to \(m.number) failed") }
        return ok
    }

    static func undo(_ issue: DisplayIssue) -> Bool {
        guard let prev = issue.previousModeNumber else { return false }
        AppLog.info("display", "restoring Edge mode \(prev)")
        return CGSDisplayModes.apply(prev, to: issue.displayID)
    }

    static func dismiss(_ issue: DisplayIssue) {
        AppDefaults.shared.set(issue.currentLabel, forKey: dismissedKey)
    }

    static func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
