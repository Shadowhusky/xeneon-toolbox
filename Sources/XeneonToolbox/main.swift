import AppKit

MainActor.assumeIsolated {
    // Must precede any other window-server interaction (window creation, event
    // requests) or it doesn't take: allows hiding the cursor while the app is in
    // the background — which the kiosk always is during touch.
    CursorController.allowBackgroundCursorControl()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
