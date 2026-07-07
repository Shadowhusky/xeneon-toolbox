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
    @State private var globalFrames: [DeckAction.ID: CGRect] = [:]
    @State private var runningApps: Set<String> = []
    @State private var screenPickerAction: DeckAction?
    @State private var editingAction: DeckAction?

    private let space = "deckgrid"
    private let columns = [GridItem(.adaptive(minimum: 178, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 14) {
            header
            // Scrolls when browsing (a big deck overflows the panel), but scrolling
            // is disabled in edit mode so the ScrollView can't swallow the reorder
            // drag — in edit mode the touch driver sends mouse drags, not scrolls.
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(deck.actions) { action in
                        DeckTile(action: action, editing: editing, lifted: dragging == action.id,
                                 running: action.kind == .app && runningApps.contains(action.target),
                                 onRun: { model.runDeck($0) })
                            // In edit mode the tiles stop consuming touches, so the grid's
                            // drag gesture actually receives them. This is the exact reason
                            // the dashboard reorder works and the deck's earlier version
                            // (a live Button on top) never did — the Button ate the drag.
                            .allowsHitTesting(!editing)
                            .background(GeometryReader { p in
                                Color.clear
                                    .preference(key: DeckFrameKey.self, value: [action.id: p.frame(in: .named(space))])
                                    .preference(key: DeckGlobalFrameKey.self, value: [action.id: p.frame(in: .global)])
                            })
                            // Remove badge sits OUTSIDE the disabled tile, so it stays tappable.
                            .overlay(alignment: .topTrailing) {
                                if editing && dragging != action.id { removeBadge(action.id) }
                            }
                            .overlay(alignment: .topLeading) {
                                if editing && dragging != action.id { editBadge(action) }
                            }
                    }
                    if editing { AddTile { withAnimation(Motion.smooth) { showAdd = true } } }
                }
                .coordinateSpace(name: space)
                .onPreferenceChange(DeckFrameKey.self) { frames = $0 }
                .onPreferenceChange(DeckGlobalFrameKey.self) { globalFrames = $0 }
                .overlay { floatingDragged }
                .contentShape(Rectangle())
                // Exactly the dashboard's working pattern: a plain drag, active over the
                // tiles only in edit mode (.all); otherwise taps pass through (.subviews).
                .gesture(reorderGesture, including: editing ? .all : .subviews)
                .padding(.bottom, 6)
            }
            .scrollDisabled(editing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The Add overlay unmounts INSTANTLY (no removal transition): an implicit
        // `.animation(value: showAdd)` used to drive its fade-out, and when
        // `deck.add` reshaped the grid in the same update the removal could stall
        // — leaving the dimming backdrop invisible but still hit-testable over
        // the whole page ("stuck deck" — can't tap Done, can't drag).
        .overlay { if showAdd { AddDeckOverlay(deck: deck) { showAdd = false }.transition(.opacity) } }
        .overlay { if showSortMenu { sortMenu } }
        .overlay { if let p = pending { confirmModal(p) } }
        .overlay { if let a = screenPickerAction { screenPicker(a) } }
        .overlay { if let a = editingAction { TileEditForm(deck: deck, action: a) { editingAction = nil } } }
        .animation(Motion.standard, value: editing)
        .animation(Motion.pop, value: screenPickerAction)
        .animation(Motion.pop, value: pending)
        .animation(Motion.pop, value: editingAction)
        // A long-press on an app tile (detected by the driver) opens a picker to
        // choose which display to open/move the app on.
        .onChange(of: model.deckLongPressAt) {
            guard !editing, let pt = model.deckLongPressAt else { return }
            model.deckLongPressAt = nil
            guard let id = globalFrames.first(where: { $0.value.contains(pt) })?.key,
                  let action = deck.actions.first(where: { $0.id == id }) else { return }
            // App tiles get the "open on which display" picker; every other kind
            // just runs — a long-press should never be a dead interaction (the
            // driver has already swallowed the tap that would have run it).
            if action.kind == .app { screenPickerAction = action }
            else { model.runDeck(action) }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["XENEON_DECK_EDIT"] != nil { editing = true }
            if ProcessInfo.processInfo.environment["XENEON_DECK_ADD"] != nil { editing = true; showAdd = true }
            if ProcessInfo.processInfo.environment["XENEON_DECK_SCREENPICKER"] != nil {
                screenPickerAction = deck.actions.first { $0.kind == .app }
            }
            syncReorderDragging()
            syncLongPress()
        }
        // While editing (and no overlay needs to scroll), the touch driver treats
        // any finger move as a mouse drag so tiles can be dragged in 2-D. Any
        // mode change also abandons an in-flight reorder drag — a gesture
        // cancelled by an overlay appearing never calls onEnded, and a stale
        // `dragging` id would wedge the grid.
        .onChange(of: editing) { dragging = nil; syncReorderDragging(); syncLongPress() }
        .onChange(of: showAdd) { dragging = nil; syncReorderDragging(); syncLongPress() }
        .onChange(of: screenPickerAction) { syncLongPress() }
        .onDisappear { dragging = nil; model.setReorderDragging(false); model.setDeckLongPress(false) }
        // Dock-style running indicators on app tiles.
        .task { refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshRunning() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.battery)
            Text("Deck").font(.deck(24, .bold)).foregroundStyle(Theme.textPrimary)
            if editing {
                Text("Drag tiles to reorder · tap ⊖ to remove")
                    .font(.deck(13, .medium)).foregroundStyle(Theme.textFaint)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
            Spacer()
            deckButton("Sort", "arrow.up.arrow.down", tint: Theme.textSecondary) { withAnimation(Motion.snappy) { showSortMenu.toggle() } }
            if editing { deckButton("Reset", "arrow.counterclockwise", tint: Theme.textSecondary) { pending = .reset } }
            deckButton(editing ? "Done" : "Edit", editing ? "checkmark" : "square.and.pencil",
                       tint: editing ? Theme.battery : Theme.textSecondary) { withAnimation(Motion.standard) { editing.toggle() } }
        }
    }

    private func deckButton(_ label: String, _ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: { AppLog.info("deck", "header button: \(label)"); action() }) {
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
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { withAnimation(Motion.snappy) { showSortMenu = false } }
            VStack(spacing: 6) {
                ForEach(DeckSort.allCases) { s in
                    Button { withAnimation(Motion.snappy) { showSortMenu = false }; requestSort(s) } label: {
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
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
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
        return ModalScaffold(onDismiss: { pending = nil }) {
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

    private func syncReorderDragging() {
        model.setReorderDragging(editing && !showAdd)
    }

    private func syncLongPress() {
        model.setDeckLongPress(!editing && !showAdd && screenPickerAction == nil)
    }

    // MARK: Screen picker (long-press an app tile)

    private func screenPicker(_ action: DeckAction) -> some View {
        let displays = WindowMover.displays()
        return ModalScaffold(onDismiss: { screenPickerAction = nil }) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    DeckActionIcon(action: action, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label).font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                        Text(runningApps.contains(action.target) ? "Move to display" : "Open on display")
                            .font(.deck(13)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 10) {
                    ForEach(displays) { d in
                        Button {
                            WindowMover.open(appPath: action.target, on: d)
                            screenPickerAction = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: d.isEdge ? "rectangle.on.rectangle.angled" : "display")
                                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(d.name).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                                    Text("\(Int(d.bounds.width))×\(Int(d.bounds.height))")
                                        .font(.deck(12)).foregroundStyle(Theme.textFaint)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.forward").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textFaint)
                            }
                            .padding(.horizontal, 16).frame(height: 60)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }.buttonStyle(.pressable)
                    }
                    if runningApps.contains(action.target) {
                        Button {
                            WindowMover.quit(appPath: action.target)
                            screenPickerAction = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Theme.batteryLow).frame(width: 30)
                                Text("Quit \(action.label)").font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16).frame(height: 60)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.batteryLow.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.batteryLow.opacity(0.4), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }.buttonStyle(.pressable)
                    }
                }
            }
            .padding(24).frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
        }
    }

    private func refreshRunning() {
        runningApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
    }

    private func removeBadge(_ id: DeckAction.ID) -> some View {
        Button { deck.remove(id) } label: {
            Image(systemName: "minus").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.batteryLow))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                .contentShape(Circle())
        }.buttonStyle(.pressable).padding(7)
    }

    private func editBadge(_ action: DeckAction) -> some View {
        Button { editingAction = action } label: {
            Image(systemName: "pencil").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.accent))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                .contentShape(Circle())
        }.buttonStyle(.pressable).padding(7)
    }

    @ViewBuilder private var floatingDragged: some View {
        if let id = dragging, let a = deck.actions.first(where: { $0.id == id }), let f = frames[id] {
            DeckTile(action: a, editing: editing, lifted: false, onRun: { _ in })
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
        withAnimation(Motion.snappy) {
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

/// Tile frames in `.global` (window) coordinates — used to hit-test the driver's
/// long-press point, which arrives in Edge-local (window) coordinates.
struct DeckGlobalFrameKey: PreferenceKey {
    static var defaultValue: [DeckAction.ID: CGRect] = [:]
    static func reduce(value: inout [DeckAction.ID: CGRect], nextValue: () -> [DeckAction.ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DeckTile: View {
    let action: DeckAction
    let editing: Bool
    var lifted: Bool = false
    var running: Bool = false
    let onRun: (DeckAction) -> Void

    private var tint: Color {
        switch action.kind {
        case .app: return Theme.accent
        case .url: return Theme.disk
        case .system: return Theme.time
        case .media: return Theme.memory
        case .command: return Theme.gpu
        case .webhook: return Theme.netUp
        case .keystroke: return Theme.battery
        case .multi: return Theme.memory
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
            .overlay(alignment: .bottom) {
                if running {
                    Circle().fill(Theme.battery).frame(width: 5, height: 5)
                        .deckGlow(Theme.battery, strength: 0.8)
                        .padding(.bottom, 8)
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
        } else if action.kind == .url, let favicon = WebController.faviconURL(action.target) {
            // Websites get their real favicon; the globe only shows while it loads
            // (or if the site has none).
            AsyncImage(url: favicon) { phase in
                if let img = phase.image {
                    img.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: "globe").font(.system(size: 30, weight: .semibold)).foregroundStyle(tint)
                }
            }
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.14)))
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
