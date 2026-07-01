import SwiftUI
import AppKit

/// A Stream-Deck-style page: a grid of big touch tiles that launch apps, open
/// websites, control media, or fire in-app system actions. Editable, sortable,
/// drag-to-reorder, and persisted.
struct DeckView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var deck: DeckStore
    @State private var editing = false
    @State private var showAdd = false
    @State private var showSortMenu = false
    @State private var pending: PendingAction?

    private enum PendingAction: Equatable { case sort(DeckSort), reset }

    @State private var dragging: DeckAction.ID?
    @State private var dragPoint: CGPoint = .zero
    @State private var dragGrab: CGSize = .zero
    @State private var frames: [DeckAction.ID: CGRect] = [:]

    private let space = "deckgrid"
    private let columns = [GridItem(.adaptive(minimum: 178, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 14) {
            header
            // No ScrollView: it would swallow the reorder drag (the dashboard reorder
            // works precisely because its grid isn't wrapped in one). Grids of this
            // size fit the Edge; overflow clips at the bottom.
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(deck.actions) { action in
                    DeckTile(action: action, editing: editing, lifted: dragging == action.id,
                             onRun: { model.runDeck($0) }, onRemove: { deck.remove($0) })
                        .background(GeometryReader { p in
                            Color.clear.preference(key: DeckFrameKey.self, value: [action.id: p.frame(in: .named(space))])
                        })
                }
                if editing { AddTile { showAdd = true } }
            }
            .coordinateSpace(name: space)
            .onPreferenceChange(DeckFrameKey.self) { frames = $0 }
            .overlay { floatingDragged }
            // Exactly the dashboard's working pattern: a plain drag, active over the
            // tiles only in edit mode (.all); otherwise taps pass through (.subviews).
            .gesture(reorderGesture, including: editing ? .all : .subviews)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay { if showAdd { AddDeckOverlay(deck: deck) { showAdd = false } } }
        .overlay { if showSortMenu { sortMenu } }
        .overlay { if let p = pending { confirmModal(p) } }
        .animation(.easeInOut(duration: 0.2), value: editing)
        .animation(.easeInOut(duration: 0.2), value: showAdd)
        .onAppear {
            if ProcessInfo.processInfo.environment["XENEON_DECK_ADD"] != nil { editing = true; showAdd = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.battery)
            Text("Deck").font(.deck(24, .bold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            deckButton("Sort", "arrow.up.arrow.down", tint: Theme.textSecondary) { withAnimation { showSortMenu.toggle() } }
            if editing { deckButton("Reset", "arrow.counterclockwise", tint: Theme.textSecondary) { pending = .reset } }
            deckButton(editing ? "Done" : "Edit", editing ? "checkmark" : "square.and.pencil",
                       tint: editing ? Theme.battery : Theme.textSecondary) { withAnimation { editing.toggle() } }
        }
    }

    private func deckButton(_ label: String, _ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(label).font(.deck(14, .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }.buttonStyle(.pressable)
    }

    // MARK: Sort

    private var sortMenu: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { withAnimation { showSortMenu = false } }
            VStack(spacing: 6) {
                ForEach(DeckSort.allCases) { s in
                    Button { withAnimation { showSortMenu = false }; requestSort(s) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.icon).font(.system(size: 14, weight: .semibold)).frame(width: 20)
                            Text(s.label).font(.deck(15, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14).frame(width: 220, height: 46)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }.buttonStyle(.pressable)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .padding(.top, 56).padding(.trailing, 4)
        }
    }

    private func requestSort(_ s: DeckSort) { pending = .sort(s) }

    private func confirmModal(_ action: PendingAction) -> some View {
        let isReset = action == .reset
        let title = isReset ? "Reset the deck?" : "Replace your current order?"
        let body = isReset
            ? "This restores the default tiles and removes everything you've added and arranged."
            : "Sorting will overwrite your current tile order. Tiles you added stay."
        let confirmLabel = isReset ? "Reset" : "Sort"
        let tint = isReset ? Theme.batteryLow : Theme.battery
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { pending = nil }
            VStack(spacing: 16) {
                Image(systemName: isReset ? "exclamationmark.triangle.fill" : "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(tint)
                Text(title).font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                Text(body).font(.deck(15)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { pending = nil } label: {
                        Text("Cancel").font(.deck(16, .semibold)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
                    }.buttonStyle(.pressable)
                    Button {
                        withAnimation {
                            switch action { case .reset: deck.reset(); case .sort(let s): deck.sort(s) }
                        }
                        pending = nil
                    } label: {
                        Text(confirmLabel).font(.deck(16, .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint))
                    }.buttonStyle(.pressable)
                }
            }
            .padding(28).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
        }
    }

    // MARK: Reorder

    @ViewBuilder private var floatingDragged: some View {
        if let id = dragging, let a = deck.actions.first(where: { $0.id == id }), let f = frames[id] {
            DeckTile(action: a, editing: editing, lifted: false, onRun: { _ in }, onRemove: { _ in })
                .frame(width: f.width, height: f.height)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
                .position(x: dragPoint.x - dragGrab.width, y: dragPoint.y - dragGrab.height)
                .allowsHitTesting(false)
        }
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
            .onChanged { v in beginOrUpdateDrag(at: v.startLocation, to: v.location) }
            .onEnded { _ in dragging = nil }
    }

    private func beginOrUpdateDrag(at start: CGPoint, to location: CGPoint) {
        if dragging == nil {
            guard let d = frames.first(where: { $0.value.contains(start) })?.key else { return }
            dragging = d
            let f = frames[d] ?? .zero
            dragGrab = CGSize(width: start.x - f.midX, height: start.y - f.midY)
        }
        guard let d = dragging else { return }
        dragPoint = location
        let center = CGPoint(x: location.x - dragGrab.width, y: location.y - dragGrab.height)
        guard let target = frames.first(where: { $0.key != d && $0.value.contains(center) }),
              let tf = frames[target.key] else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            deck.move(d, target: target.key, before: center.x < tf.midX)
        }
    }
}

struct DeckFrameKey: PreferenceKey {
    static var defaultValue: [DeckAction.ID: CGRect] = [:]
    static func reduce(value: inout [DeckAction.ID: CGRect], nextValue: () -> [DeckAction.ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DeckTile: View {
    let action: DeckAction
    let editing: Bool
    var lifted: Bool = false
    let onRun: (DeckAction) -> Void
    let onRemove: (DeckAction.ID) -> Void

    private var tint: Color {
        switch action.kind {
        case .app: return Theme.accent
        case .url: return Theme.disk
        case .system: return Theme.time
        case .media: return Theme.memory
        case .command: return Theme.gpu
        case .webhook: return Theme.netUp
        }
    }

    var body: some View {
        Button { if !editing { onRun(action) } } label: {
            VStack(spacing: 12) {
                icon
                Text(action.label).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.16), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button { onRemove(action.id) } label: {
                        Image(systemName: "minus").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.batteryLow))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                            .contentShape(Circle())
                    }.buttonStyle(.plain).padding(7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
        .opacity(lifted ? 0 : 1)
        .overlay {
            if editing && !lifted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if let img = action.customImage {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let img = action.appIcon {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: 60, height: 60)
        } else {
            Image(systemName: action.symbol ?? "app.dashed").font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.14)))
        }
    }
}

private struct AddTile: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.textSecondary)
                Text("Add").font(.deck(14, .semibold)).foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity).frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(Theme.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(.pressable)
    }
}
