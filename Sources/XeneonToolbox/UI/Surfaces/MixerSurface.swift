import SwiftUI

struct MixerSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .mixer, onBack: onBack) {
            SurfaceNotice(icon: Surface.mixer.icon, title: "Coming together", message: Surface.mixer.blurb)
        }
    }
}
