import SwiftUI

struct PrompterSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .prompter, onBack: onBack) {
            SurfaceNotice(icon: Surface.prompter.icon, title: "Coming together", message: Surface.prompter.blurb)
        }
    }
}
