import AppKit
import SwiftUI

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Lets a tap act immediately even when the window isn't focused, so injected
/// touches don't get "eaten" as a mere focus click (the refocus-with-mouse bug).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = ToolboxModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
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
        win.acceptsMouseMovedEvents = true
        win.contentView = FirstMouseHostingView(rootView: RootView(model: model, metrics: model.metrics))
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

    /// Without a main menu, standard editing shortcuts (⌘A select-all, ⌘C/⌘V,
    /// undo) never reach the focused text field. This wires them up.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Xeneon Toolbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = main
    }

    private func edgeScreen() -> NSScreen? {
        NSScreen.screens.first {
            abs($0.frame.width - 2560) < 2 && abs($0.frame.height - 720) < 2
        }
    }
}
