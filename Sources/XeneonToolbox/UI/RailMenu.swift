import SwiftUI

/// The rail's "⋯" menu: screen modes, hide, edit, settings, quit — big rows
/// anchored beside the rail.
struct RailMenu: View {
    let model: ToolboxModel
    var onClose: () -> Void

    var body: some View {
        ModalScaffold(dim: 0.45, onDismiss: onClose) {
            VStack(spacing: 6) {
                row("Full screen", "arrow.up.left.and.arrow.down.right", Theme.accent) { model.toggleFullscreen() }
                row("Ambient screen", "rectangle.compress.vertical", Theme.accent) { model.setDisplay(.minimal) }
                row("Sleep", "moon.fill", Theme.time) { model.setDisplay(.sleep) }
                row("Hide · use the screen", "pip.enter", Theme.accent) { model.hideToBadge() }
                if model.route == .dashboard {
                    row("Edit dashboard", "square.grid.3x2", Theme.battery) { model.dashboardCommands.editing = true }
                }
                row("Settings", "gearshape.fill", Theme.textSecondary) { model.showSettings = true }
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 4)
                row("Quit Xeneon Toolbox", "power", Theme.batteryLow) { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 124).padding(.bottom, 18)
        }
    }

    private func row(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button { onClose(); action() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).frame(width: 26)
                Text(title).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(height: 58).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}
