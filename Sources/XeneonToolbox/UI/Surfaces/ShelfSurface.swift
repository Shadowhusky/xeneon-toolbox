import SwiftUI

struct ShelfSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .shelf, onBack: onBack) {
            SurfaceNotice(icon: Surface.shelf.icon, title: "Coming together", message: Surface.shelf.blurb)
        }
    }
}
