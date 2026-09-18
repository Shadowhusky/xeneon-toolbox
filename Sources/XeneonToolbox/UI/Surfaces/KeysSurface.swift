import SwiftUI

struct KeysSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .keys, onBack: onBack) {
            SurfaceNotice(icon: Surface.keys.icon, title: "Coming together", message: Surface.keys.blurb)
        }
    }
}
