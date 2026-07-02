import AppKit
import UniformTypeIdentifiers

/// Opens files from a panel that actually shows *above* the kiosk window.
///
/// The main window is pinned above the menu bar (level `mainMenu + 1`) so nothing
/// can cover the Edge. A default `NSOpenPanel` opens at the ordinary modal level,
/// which lands *behind* that window — the picker appears to do nothing. Raising the
/// panel's level above the kiosk and activating the app fixes it.
enum FilePanel {
    @MainActor
    static func open(contentTypes: [UTType], message: String? = nil, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = prompt
        if let message { panel.message = message }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)

        // The kiosk is a non-activating panel, so picking a file is one of the few
        // moments we deliberately bring the app forward — otherwise the modal loop
        // can't take keyboard focus and the sheet reads as unresponsive.
        NSApp.activate(ignoringOtherApps: true)

        return panel.runModal() == .OK ? panel.url : nil
    }
}
