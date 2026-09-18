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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Surfaces").font(.deck(26, .semibold)).foregroundStyle(Theme.textPrimary)
                Text("The whole strip, turned into one instrument at a time.").font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
            }
            // Two rows of five that share the height, whatever it is.
            let rows = stride(from: 0, to: Surface.allCases.count, by: 5).map { Array(Surface.allCases.dropFirst($0).prefix(5)) }
            VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 14) {
                        ForEach(rows[r]) { s in
                            Button { model.surface = s } label: { card(s) }.buttonStyle(.pressable)
                        }
                        if rows[r].count < 5 { edgeHint }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func card(_ s: Surface) -> some View {
        TileSurface(accent: s.tint) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: s.icon).font(.system(size: 24, weight: .bold)).foregroundStyle(s.tint)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(s.tint.opacity(0.14)))
                Spacer(minLength: 0)
                Text(s.title).font(.deck(21, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(s.blurb).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(minHeight: 56, alignment: .top)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
    }

    /// Not a surface: the two sliders that work from any screen.
    private var edgeHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anywhere").font(.deckLabel).foregroundStyle(Theme.textFaint)
            hint("speaker.wave.2.fill", Theme.accent, "Slide along the bottom edge for volume")
            if model.canControlBacklight { hint("sun.max.fill", Theme.ice, "Slide along the top edge for brightness") }
            hint("arrow.left.and.right", Theme.textSecondary, "Swipe in from a side to change page")
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous).strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
    }

    private func hint(_ icon: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint).frame(width: 24)
            Text(text).font(.deck(14, .medium)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
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
