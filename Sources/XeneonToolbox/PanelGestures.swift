import SwiftUI

/// Finger-driven values that change at touch rate (60–120 Hz while a gesture is
/// in flight). Kept apart from the coordinator model so only the overlays that
/// draw them re-render — not the whole panel.
@MainActor
final class PanelGestures: ObservableObject {
    /// 0…1 bottom edge of the ambient screen while it's being dragged in or out.
    @Published var pullFrac: Double?
    /// 0…1 how far the control centre is pulled down.
    @Published var controlExt: Double = 0
    /// A driver long-press, in Edge-local (window) coordinates.
    @Published var longPressAt: CGPoint?
    /// The level an edge slide is setting, while the finger is down and a moment after.
    @Published var edgeLevel: EdgeLevel?

    struct EdgeLevel: Equatable {
        enum Kind { case volume, brightness }
        let kind: Kind
        var value: Double
    }
}
