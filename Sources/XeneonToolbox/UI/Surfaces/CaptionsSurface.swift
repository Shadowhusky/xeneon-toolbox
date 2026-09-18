import SwiftUI

struct CaptionsSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .captions, onBack: onBack) {
            SurfaceNotice(icon: Surface.captions.icon, title: "Coming together", message: Surface.captions.blurb)
        }
    }
}
