import SwiftUI

struct AgentsSurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .agents, onBack: onBack) {
            SurfaceNotice(icon: Surface.agents.icon, title: "Coming together", message: Surface.agents.blurb)
        }
    }
}
