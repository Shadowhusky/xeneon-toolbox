import SwiftUI

/// The Surfaces page: a grid of surfaces, or the one that's open.
struct SurfacesView: View {
    @ObservedObject var model: ToolboxModel

    var body: some View {
        Group {
            if let surface = model.surface {
                open(surface).transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                grid.transition(.opacity)
            }
        }
        .animation(Motion.page, value: model.surface)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Surfaces").font(.deck(26, .semibold)).foregroundStyle(Theme.textPrimary)
                Text("The whole strip, turned into one instrument at a time.").font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Surface.allCases) { s in
                    Button { model.surface = s } label: { card(s) }.buttonStyle(.pressable)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func card(_ s: Surface) -> some View {
        TileSurface(accent: s.tint) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: s.icon).font(.system(size: 22, weight: .bold)).foregroundStyle(s.tint)
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(s.tint.opacity(0.14)))
                Spacer(minLength: 0)
                Text(s.title).font(.deck(19, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(s.blurb).font(.deck(13, .medium)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(minHeight: 50, alignment: .top)
            }
        }
        .frame(height: 252)
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
    }

    @ViewBuilder private func open(_ surface: Surface) -> some View {
        let back = { model.surface = nil }
        switch surface {
        case .mixer: MixerSurface(model: model, onBack: back)
        case .scrub: ScrubSurface(model: model, onBack: back)
        case .keys: KeysSurface(model: model, onBack: back)
        case .windows: WindowMapSurface(model: model, onBack: back)
        case .shelf: ShelfSurface(model: model, onBack: back)
        case .captions: CaptionsSurface(model: model, onBack: back)
        case .prompter: PrompterSurface(model: model, onBack: back)
        case .agents: AgentsSurface(model: model, onBack: back)
        case .telemetry: TelemetrySurface(model: model, onBack: back)
        }
    }
}
