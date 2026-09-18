import SwiftUI

struct ScrubSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .scrub, onBack: onBack) {
            SurfaceNotice(icon: Surface.scrub.icon, title: "Coming together", message: Surface.scrub.blurb)
        }
    }
}
