import AppKit
import SwiftUI

/// Borderless windows can't become key by default, which blocks button taps.
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

        let win = KeyableWindow(contentRect: frame, styleMask: [.borderless],
                                backing: .buffered, defer: false)
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = false
        win.level = .normal
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: PanelView(model: model, metrics: model.metrics))
        host.frame = NSRect(origin: .zero, size: frame.size)
        win.contentView = host
        win.setFrame(frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fputs("WINDOW_ID=\(win.windowNumber)\n", stderr)

        self.window = win
        model.onAppear()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func edgeScreen() -> NSScreen? {
        NSScreen.screens.first {
            abs($0.frame.width - 2560) < 2 && abs($0.frame.height - 720) < 2
        }
    }
}
