import AppKit
import SwiftUI

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = ToolboxModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = edgeScreen() ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 2560, height: 720)
        let devMode = ProcessInfo.processInfo.environment["XENEON_NO_FULLSCREEN"] != nil

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let win = KeyableWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        win.title = "Xeneon Toolbox"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = false

        win.collectionBehavior = [.fullScreenPrimary]
        win.contentView = NSHostingView(rootView: RootView(model: model, metrics: model.metrics))
        win.setFrame(frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fputs("WINDOW_ID=\(win.windowNumber)\n", stderr)

        self.window = win
        model.onAppear()

        // Default to native fullscreen on the Edge — this hides the system menu
        // bar and gives the panel the whole display. Skipped in dev for capture.
        if !devMode {
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !win.styleMask.contains(.fullScreen) { win.toggleFullScreen(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func edgeScreen() -> NSScreen? {
        NSScreen.screens.first {
            abs($0.frame.width - 2560) < 2 && abs($0.frame.height - 720) < 2
        }
    }
}
