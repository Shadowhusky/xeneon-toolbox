import SwiftUI

struct WindowMapSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .windows, onBack: onBack) {
            SurfaceNotice(icon: Surface.windows.icon, title: "Coming together", message: Surface.windows.blurb)
        }
    }
}
