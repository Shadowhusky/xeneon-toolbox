import SwiftUI

/// Every tile not yet on the board, with a size to add it at.
struct TileGalleryOverlay: View {
    @ObservedObject var layout: DashboardLayout
    var onClose: () -> Void

    var body: some View {
        ModalScaffold(onDismiss: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add a tile").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)
                        Text("\(layout.cellsUsed) of \(DashboardLayout.capacity) cells used · S = 1 cell, W and T = 2")
                            .font(.deck(13)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 42, height: 42).background(Circle().fill(Color.white.opacity(0.07))).contentShape(Circle())
                    }.buttonStyle(.pressable)
                }
                if layout.available.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.battery)
                        Text("Every tile is already on the board").font(.deck(16, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if ProcessInfo.processInfo.environment["XENEON_RENDER"] != nil {
                    // ScrollView content doesn't lay out in the off-screen renderer.
                    VStack(spacing: 8) { ForEach(layout.available) { row($0) } }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(layout.available) { row($0) }
                        }
                    }
                    .frame(maxHeight: 460)
                }
            }
            .padding(24).frame(width: 780)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 28, y: 10)
        }
    }

    private func row(_ tile: DashTile) -> some View {
        HStack(spacing: 14) {
            Image(systemName: tile.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44).background(Circle().fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.title).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(tile.blurb).font(.deck(13)).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(tile.sizes, id: \.self) { size in sizeButton(tile, size) }
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 72)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func sizeButton(_ tile: DashTile, _ size: TileSize) -> some View {
        let room = layout.cellsUsed + size.cells <= DashboardLayout.capacity
        return Button {
            if layout.add(tile, size: size) { onClose() }
        } label: {
            VStack(spacing: 2) {
                Text(size.label).font(.readout(15, .bold))
                Text(size.name).font(.deck(10, .semibold))
            }
            .foregroundStyle(room ? Theme.textPrimary : Theme.textFaint)
            .frame(width: 64, height: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(room ? Theme.accent.opacity(0.14) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(room ? Theme.accent.opacity(0.5) : Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!room)
    }
}
