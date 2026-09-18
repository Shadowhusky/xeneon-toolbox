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
                row("Ambient screen", "rectangle.compress.vertical", Theme.ice) { model.setDisplay(.minimal) }
                row("Sleep", "moon.fill", Theme.gpu) { model.setDisplay(.sleep) }
                row("Hide and use the screen", "pip.enter", Theme.ice) { model.hideToBadge() }
                if model.route == .dashboard {
                    row("Edit dashboard", "square.grid.3x2", Theme.battery) { model.dashboardCommands.editing = true }
                }
                row("Settings", "gearshape.fill", Theme.textSecondary) { model.showSettings = true }
                if let s = model.updater.staged {
                    row("Restart to update to v\(s.version)", "arrow.down.circle.fill", Theme.accent) { model.updater.installNow() }
                }
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 4)
                row("Quit Xeneon Toolbox", "power", Theme.batteryLow) { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 22)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
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
