import AppKit
import SwiftUI

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // A touchscreen deck has no keyboard chrome; if a keystroke reaches the window
    // unhandled (no text field or game focused), swallow it instead of letting
    // macOS sound the system alert beep. Menu shortcuts (⌘C etc.) use a separate
    // key-equivalent path and are unaffected.
    override func keyDown(with event: NSEvent) { /* swallow — no beep */ }
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
    private var noNapToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        // The touch driver reads the digitizer on the main run loop. When the app
        // isn't frontmost (you're working on another screen), App Nap would
        // throttle that loop and touch would freeze until you click back in.
        // Holding a user-initiated, latency-critical activity disables App Nap so
        // touch keeps working continuously.
        noNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Xeneon Edge touch input runs continuously, including while another app is focused")

        // Headless high-res export: render the UI off-screen at NxN scale (the UI
        // is vector, so this is far crisper than capturing the 2560x720 panel).
        // XENEON_RENDER="route@scale@warmupSeconds@/abs/out.png"
        if let spec = ProcessInfo.processInfo.environment["XENEON_RENDER"] {
            renderOffscreenThenExit(spec)
            return
        }

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

    // Re-seize the digitizer whenever the app regains focus, so tapping back into
    // it from another screen re-engages touch immediately.
    func applicationDidBecomeActive(_ notification: Notification) {
        model.reacquireTouch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.restoreBacklightOnQuit()   // don't leave the Edge dark if we quit while asleep
    }

    private func renderOffscreenThenExit(_ spec: String) {
        let parts = spec.components(separatedBy: "@")
        guard parts.count == 4, let scale = Double(parts[1]), let warmup = Double(parts[2]) else {
            fputs("XENEON_RENDER bad spec; expected route@scale@warmup@/path\n", stderr); NSApp.terminate(nil); return
        }
        let route = parts[0], outPath = parts[3]
        if let r = AppRoute(rawValue: route == "assistant" ? "chat" : route) { model.route = r }
        if route == "minimal" { model.displayMode = .minimal }
        else if route == "sleep" { model.displayMode = .sleep }
        else { model.displayMode = .full }   // render the actual page, not the minimal overlay
        model.exportMode = true   // static add bars / non-scroll lists for off-screen render
        if route == "assistant" {
            model.agent.turns = [
                .init(role: "user", text: "Compare the RTX 4090, RTX 4080 Super, and RX 7900 XTX"),
                .init(role: "card", text: "", card: .table(title: "GPU Comparison",
                    headers: ["GPU", "VRAM", "TDP", "MSRP"],
                    rows: [["RTX 4090", "24 GB", "450 W", "$1599"],
                           ["RTX 4080 Super", "16 GB", "320 W", "$999"],
                           ["RX 7900 XTX", "24 GB", "355 W", "$949"]])),
                .init(role: "assistant", text: "The **4090** leads on raw performance; the **7900 XTX** matches its VRAM for less. The **4080 Super** is the efficiency pick."),
            ]
        }
        model.touchOn = true; model.edgeDetected = true   // show Touch "Active" in demo renders
        model.metrics.start()
        model.weather.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + warmup) { [self] in
            let content = RootView(model: model, metrics: model.metrics)
                .frame(width: 2560, height: 720)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = CGFloat(scale)
            guard let cg = renderer.cgImage else { fputs("render failed\n", stderr); NSApp.terminate(nil); return }
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outPath))
                fputs("RENDERED \(cg.width)x\(cg.height) -> \(outPath)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }

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
