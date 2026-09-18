import SwiftUI
import AppKit

struct DetailAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var tint: Color = Theme.textPrimary
    let run: () -> Void
}

/// The frame every detail panel shares: nearly the whole strip, a header with
/// the live readout and the panel's actions, and room for three columns.
struct DetailShell<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var subtitle: String? = nil
    var actions: [DetailAction] = []
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(tint.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.deck(24, .semibold)).foregroundStyle(Theme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 16)
                ForEach(actions) { a in
                    GhostButton(title: a.title, icon: a.icon, tint: a.tint, height: 46, action: a.run)
                }
                CircleIconButton(icon: "xmark", size: 46, action: onClose)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(26)
        .frame(maxWidth: 2260, maxHeight: 656)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop.opacity(0.96), Theme.tileBottom.opacity(0.96)], startPoint: .top, endPoint: .bottom)))
        .bezel(corner: 28, tint: tint)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        .padding(.horizontal, 36).padding(.vertical, 26)
    }
}

/// A titled well inside a detail panel.
struct ConsolePanel<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.deckLabel).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.readout(12, .medium)).foregroundStyle(Theme.textFaint) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.wellFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
    }
}

/// The panel's headline number.
struct HeroStat: View {
    let value: String
    var unit: String = ""
    let caption: String
    let tint: Color
    var size: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.hero(size)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.readout(size * 0.3, .semibold)).foregroundStyle(tint) }
            }
            Text(caption).font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct MiniStat: View {
    let value: String
    let caption: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.readout(24, .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.deck(12, .medium)).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled fact, optionally with a copy button big enough for a finger.
struct FactRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = Theme.textSecondary
    var copyable = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 24)
            Text(label).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 10)
            Text(value).font(.readout(15, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            if copyable {
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(copied ? Theme.battery : Theme.textSecondary)
                        .frame(width: 44, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                        .contentShape(Rectangle())
                }.buttonStyle(.pressable)
            }
        }
        .frame(minHeight: 40)
    }
}

/// A history graph with quiet guide lines and a scale.
struct GridGraph: View {
    var series: [(values: [Double], color: Color)]
    var ceiling: Double? = nil
    var topLabel: String? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    Spacer(minLength: 0)
                }
                Rectangle().fill(Theme.stroke).frame(height: 1)
            }
            ForEach(series.indices, id: \.self) { i in
                Sparkline(values: series[i].values, color: series[i].color, fillOpacity: series.count > 1 ? 0.08 : 0.2, ceiling: ceiling)
            }
            if let topLabel {
                Text(topLabel).font(.readout(11, .medium)).foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.background.opacity(0.7)))
                    .padding(.top, 8).padding(.trailing, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.wellFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
    }
}

/// A thin horizontal meter with its label and value.
struct MeterRow: View {
    let label: String
    let fraction: Double
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value).font(.readout(14, .semibold)).foregroundStyle(Theme.textPrimary)
            }
            CapacityBar(fraction: fraction, color: tint).frame(height: 8)
        }
    }
}

/// The busiest processes, with a Quit button on the ones that are apps.
struct ProcessTable: View {
    let title: String
    var note: String? = nil
    let rows: [ProcRow]
    let byMemory: Bool
    let tint: Color
    var limit = 8
    @State private var quitting: Set<Int32> = []

    var body: some View {
        ConsolePanel(title: title, trailing: note) {
            if rows.isEmpty {
                Text("Reading processes…").font(.deck(14)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let shown = Array(rows.prefix(limit)), top = max(1, shown.map(\.rssMB).max() ?? 1)
                let canQuit = shown.contains { Self.quittable($0) }
                VStack(spacing: 4) {
                    ForEach(shown) { r in row(r, top: top, quitSlot: canQuit) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private static func quittable(_ r: ProcRow) -> Bool {
        r.pid != ProcessInfo.processInfo.processIdentifier && NSRunningApplication(processIdentifier: r.pid)?.activationPolicy == .regular
    }

    private func row(_ r: ProcRow, top: Double, quitSlot: Bool) -> some View {
        let app = NSRunningApplication(processIdentifier: r.pid)
        let quittable = Self.quittable(r)
        let fraction = byMemory ? min(1, r.rssMB / top) : min(1, r.cpu / 100)
        return HStack(spacing: 10) {
            Group {
                if let icon = app?.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                else { Image(systemName: "gearshape.2").font(.system(size: 13)).foregroundStyle(Theme.textFaint) }
            }
            .frame(width: 24, height: 24)
            Text(app?.localizedName ?? r.name).font(.deck(14, .medium)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.middle).frame(width: 220, alignment: .leading)
            CapacityBar(fraction: fraction, color: tint).frame(height: 8)
            Text(byMemory ? Self.size(r.rssMB) : "\(Int(r.cpu.rounded()))%")
                .font(.readout(14, .semibold)).foregroundStyle(tint).frame(width: 72, alignment: .trailing)
            if quittable, let app {
                Button {
                    quitting.insert(r.pid); app.terminate()
                } label: {
                    Text(quitting.contains(r.pid) ? "Quitting" : "Quit").font(.deck(13, .semibold))
                        .foregroundStyle(quitting.contains(r.pid) ? Theme.textFaint : Theme.textPrimary)
                        .frame(width: 76, height: 40)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable).disabled(quitting.contains(r.pid))
            } else if quitSlot {
                Color.clear.frame(width: 76, height: 40)
            }
        }
        .frame(minHeight: 44, maxHeight: 56)
    }

    static func size(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
