import AppKit
import XeneonTouchDriver

/// App-side view of the connected Edge: the driver's identity lookup plus the
/// display name AppKit knows (the driver module has no AppKit).
enum EdgeScreen {
    static func nameHint(_ id: CGDirectDisplayID) -> String? {
        screen(for: id)?.localizedName
    }

    static func current() -> EdgeDisplay? { EdgeDisplayLocator.current(nameHint: nameHint) }

    static func isEdge(_ id: CGDirectDisplayID) -> Bool { EdgeDisplayLocator.isEdge(id, nameHint: nameHint) }

    static func nsScreen() -> NSScreen? { current().flatMap { screen(for: $0.id) } }

    static var isPresent: Bool { current() != nil }

    static var origin: CGPoint { current()?.bounds.origin ?? .zero }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }
    }
}
