import SwiftUI

struct TelemetrySurface: View {
    @ObservedObject var model: ToolboxModel
    let onBack: () -> Void

    var body: some View {
        SurfaceShell(surface: .telemetry, onBack: onBack) {
            SurfaceNotice(icon: Surface.telemetry.icon, title: "Coming together", message: Surface.telemetry.blurb)
        }
    }
}
