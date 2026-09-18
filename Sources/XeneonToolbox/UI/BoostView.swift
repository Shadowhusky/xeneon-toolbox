import SwiftUI
import ToolboxKit

/// Boost: see what's heavy, quit what you're not using, get memory and CPU back.
struct BoostView: View {
    @ObservedObject var scanner: BoostScanner
    var memoryUsedGB: Double
    var memoryTotalGB: Double
    var memoryPressure: Double
    var onClose: () -> Void

    @State private var quitting = false
    private static let perColumn = 7

    var body: some View {
        ModalScaffold(dim: 0.62, onDismiss: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(Theme.accent.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Boost").font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Quit apps you're not using to give memory and CPU back. Anything with unsaved work asks first.")
                            .font(.deck(13)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if memoryTotalGB > 0 { memoryPill }
                    CircleIconButton(icon: "xmark", size: 42, action: onClose)
                }

                if scanner.candidates.isEmpty {
                    VStack(spacing: 10) {
                        if scanner.scanning { DeckSpinner(size: 32) } else {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(Theme.battery)
                        }
                        Text(scanner.scanning ? "Looking at what's running…" : "Nothing else is running")
                            .font(.deck(15, .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Two columns of the heaviest apps; the modal is exactly one panel tall.
                    let rows = Array(scanner.candidates.prefix(Self.perColumn * 2))
                    let split = (rows.count + 1) / 2
                    let hidden = scanner.candidates.count - rows.count
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            column(Array(rows.prefix(split)))
                            column(Array(rows.dropFirst(split)))
                        }
                        if hidden > 0 {
                            Text("and \(hidden) smaller \(hidden == 1 ? "app" : "apps")").font(.deck(12)).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                HStack(spacing: 12) {
                    if let freed = scanner.lastFreedMB {
                        Label(freed >= 1024 ? String(format: "Freed about %.1f GB", freed / 1024) : "Freed about \(Int(freed)) MB",
                              systemImage: "sparkles")
                            .font(.deck(14, .semibold)).foregroundStyle(Theme.battery)
                    }
                    Spacer(minLength: 0)
                    GhostButton(title: "Select suggested", icon: "wand.and.stars", tint: Theme.textSecondary, height: 46) {
                        scanner.selected = Set(scanner.candidates.filter(\.suggested).map(\.id))
                    }
                    PrimaryButton(title: quitTitle, icon: "bolt.fill", height: 46) {
                        quitting = true
                        Task { await scanner.quitSelected(); quitting = false }
                    }
                    .disabled(scanner.selected.isEmpty || quitting)
                    .opacity(scanner.selected.isEmpty ? 0.5 : 1)
                }
            }
            .padding(24)
            .frame(width: 1180, height: 600)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 26, tint: Theme.accent)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        }
        .task { await scanner.scan() }
    }

    private var quitTitle: String {
        let n = scanner.selected.count
        return quitting ? "Quitting…" : n == 0 ? "Quit apps" : n == 1 ? "Quit 1 app" : "Quit \(n) apps"
    }

    private var memoryPill: some View {
        HStack(spacing: 8) {
            Lamp(color: Theme.pressure(memoryPressure, base: Theme.battery), on: true, size: 7)
            Text(String(format: "%.1f / %.0f GB", memoryUsedGB, memoryTotalGB)).font(.readout(14, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("in use").font(.deck(12)).foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(Capsule().fill(Theme.wellFill))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
    }

    private func column(_ rows: [BoostCandidate]) -> some View {
        VStack(spacing: 6) {
            ForEach(rows) { row($0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ c: BoostCandidate) -> some View {
        let on = scanner.selected.contains(c.id)
        return Button {
            if on { scanner.selected.remove(c.id) } else { scanner.selected.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(on ? Theme.accent : Theme.textFaint)
                if let icon = c.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(c.isFrontmost ? "In front" : c.suggested ? "Heavy and in the background" : "In the background")
                        .font(.deck(11, .medium)).foregroundStyle(c.suggested ? Theme.accent : Theme.textFaint)
                }
                Spacer(minLength: 8)
                Text(c.rssMB >= 1024 ? String(format: "%.1f GB", c.rssMB / 1024) : "\(Int(c.rssMB)) MB")
                    .font(.readout(13, .semibold)).foregroundStyle(Theme.textPrimary).frame(width: 74, alignment: .trailing)
                Text(String(format: "%.0f%%", c.cpu)).font(.readout(12, .medium))
                    .foregroundStyle(c.cpu >= 30 ? Theme.heat : Theme.textFaint).frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous)
                .fill(on ? Theme.accent.opacity(0.10) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.35) : Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}
