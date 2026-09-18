import SwiftUI
import AppKit

/// A Stream-Deck-style page: a grid of big touch tiles that launch apps, open
/// websites, control media, or fire in-app system actions. Editable, sortable,
/// drag-to-reorder, and persisted.
struct DeckView: View {
    let model: ToolboxModel
    @ObservedObject var deck: DeckStore
    @ObservedObject var gestures: PanelGestures
    @State private var editing = false
    @State private var showAdd = false
    @State private var showSortMenu = false
    @State private var showPageManager = false
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
            deckScroller
        }
        // The Add overlay unmounts INSTANTLY (no removal transition): an implicit
        // `.animation(value: showAdd)` used to drive its fade-out, and when
        // `deck.add` reshaped the grid in the same update the removal could stall
        // — leaving the dimming backdrop invisible but still hit-testable over
        // the whole page ("stuck deck" — can't tap Done, can't drag).
        .overlay { if showAdd { AddDeckOverlay(deck: deck) { showAdd = false }.transition(.opacity) } }
        .overlay { if showPageManager { DeckPageManager(deck: deck) { showPageManager = false } } }
        .overlay { if showSortMenu { sortMenu } }
        .overlay { if let p = pending { confirmModal(p) } }
        .overlay {
            if let a = screenPickerAction {
                ScreenPickerOverlay(model: model, deck: deck, action: a, running: runningApps.contains(a.target)) { screenPickerAction = nil }
            }
        }
        .overlay { if let a = editingAction { TileEditForm(deck: deck, action: a) { editingAction = nil } } }
        .animation(Motion.standard, value: editing)
        .animation(Motion.pop, value: showPageManager)
        .animation(Motion.pop, value: screenPickerAction)
        .animation(Motion.pop, value: pending)
        .animation(Motion.pop, value: editingAction)
        // A long-press on an app tile (detected by the driver) opens a picker to
        // choose which display to open/move the app on.
        .onChange(of: gestures.longPressAt) {
            guard !editing, let pt = gestures.longPressAt else { return }
            gestures.longPressAt = nil
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
            if ProcessInfo.processInfo.environment["XENEON_DECK_PAGES"] != nil { showPageManager = true }
            if let v = ProcessInfo.processInfo.environment["XENEON_DECK_SCREENPICKER"] {
                // "1" = first app tile; any other value picks the tile by label.
                screenPickerAction = deck.actions.first { $0.kind == .app && (v == "1" || $0.label == v) }
            }
            // Headless check of select-then-place: "<tile label>|<screen name>"
            // opens the picker; the picker arms and places (see ScreenPickerOverlay).
            if let spec = ProcessInfo.processInfo.environment["XENEON_TEST_PLACE"] {
                let label = spec.split(separator: "|").map(String.init).first ?? ""
                screenPickerAction = deck.actions.first(where: { $0.kind == .app && $0.label == label })
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
        .onChange(of: showPageManager) { dragging = nil; syncReorderDragging(); syncLongPress() }
        .onChange(of: deck.selectedPageID) {
            dragging = nil
            frames = [:]
            globalFrames = [:]
            screenPickerAction = nil
        }
        .onChange(of: screenPickerAction) { syncLongPress() }
        .onDisappear { dragging = nil; model.setReorderDragging(false); model.setLongPressEnabled(false) }
        // Dock-style running indicators on app tiles.
        .task { refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshRunning() }
    }

    private var deckScroller: some View {
        // Scrolls when browsing (a big deck overflows the panel), but scrolling
        // is disabled in edit mode so the ScrollView can't swallow the reorder drag.
        ScrollView(showsIndicators: false) {
            Group {
                if deck.actions.isEmpty && !editing { emptyState }
                else { tileGrid }
            }
            .padding(.bottom, 6)
        }
        .scrollDisabled(editing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tileGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(deck.actions) { action in tile(action) }
            if editing { AddTile { withAnimation(Motion.smooth) { showAdd = true } } }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(DeckFrameKey.self) { frames = $0 }
        .onPreferenceChange(DeckGlobalFrameKey.self) { globalFrames = $0 }
        .overlay { floatingDragged }
        .contentShape(Rectangle())
        .gesture(reorderGesture, including: editing ? .all : .subviews)
    }

    private func tile(_ action: DeckAction) -> some View {
        DeckTile(action: action, editing: editing, lifted: dragging == action.id,
                 running: action.kind == .app && runningApps.contains(action.target),
                 pinned: action.kind == .app && action.preferredDisplay != nil,
                 onRun: { model.runDeck($0) })
            // In edit mode the live Button stops consuming touches so the grid can reorder.
            .allowsHitTesting(!editing)
            .background(GeometryReader { p in
                Color.clear
                    .preference(key: DeckFrameKey.self, value: [action.id: p.frame(in: .named(space))])
                    .preference(key: DeckGlobalFrameKey.self, value: [action.id: p.frame(in: .global)])
            })
            .overlay(alignment: .topTrailing) {
                if editing && dragging != action.id { removeBadge(action.id) }
            }
            .overlay(alignment: .topLeading) {
                if editing && dragging != action.id { editBadge(action) }
            }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.battery)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(Theme.battery.opacity(0.14)))
            Text("Deck").font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
            pageNavigator
            if editing {
                Text("Drag tiles to reorder. Tap ⊖ to remove.")
                    .font(.deck(13, .medium)).foregroundStyle(Theme.textFaint)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
            Spacer()
            if deck.actions.count > 1 {
                deckButton("Sort", "arrow.up.arrow.down", tint: Theme.textSecondary) { withAnimation(Motion.snappy) { showSortMenu.toggle() } }
            }
            if editing { deckButton("Reset", "arrow.counterclockwise", tint: Theme.textSecondary) { pending = .reset } }
            deckButton(editing ? "Done" : "Edit", editing ? "checkmark" : "square.and.pencil",
                       tint: editing ? Theme.battery : Theme.textSecondary) { withAnimation(Motion.standard) { editing.toggle() } }
        }
    }

    private var pageNavigator: some View {
        HStack(spacing: 4) {
            Button { deck.selectPreviousPage() } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                    .frame(width: 34, height: 38)
            }
            .buttonStyle(.pressable)
            .disabled(deck.selectedPageID == deck.pages.first?.id)

            Button { showPageManager = true } label: {
                VStack(spacing: 0) {
                    Text(deck.selectedPage.name).font(.deck(13, .semibold)).lineLimit(1)
                    Text("\((deck.pages.firstIndex { $0.id == deck.selectedPageID } ?? 0) + 1) of \(deck.pages.count)")
                        .font(.readout(10, .semibold)).foregroundStyle(Theme.textFaint)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).frame(minWidth: 112, maxWidth: 180, minHeight: 38)
                .background(Capsule().fill(Theme.wellFill))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                .contentShape(Capsule())
            }.buttonStyle(.pressable)

            Button { deck.selectNextPage() } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .frame(width: 34, height: 38)
            }
            .buttonStyle(.pressable)
            .disabled(deck.selectedPageID == deck.pages.last?.id)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.leading, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(Theme.battery)
                .deckGlow(Theme.battery, strength: 0.7)
            Text("This page is ready for your shortcuts")
                .font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Add apps, websites, hotkeys, commands, media controls, or multi-step actions.")
                .font(.deck(14)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Add your first tile", icon: "plus", height: 50) {
                editing = true
                showAdd = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 118)
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
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
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
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 16)
            .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
            .padding(.top, 56).padding(.trailing, 4)
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private func requestSort(_ s: DeckSort) { pending = .sort(s) }

    private func confirmModal(_ action: PendingAction) -> some View {
        let isReset = action == .reset
        let title = isReset ? "Reset this page?" : "Replace your current order?"
        let body = isReset
            ? "This restores the starter tiles on “\(deck.selectedPage.name)” and removes everything you've added to this page."
            : "Sorting will overwrite your current tile order. Tiles you added stay."
        let confirmLabel = isReset ? "Reset" : "Sort"
        let tint = isReset ? Theme.batteryLow : Theme.battery
        return ModalScaffold(onDismiss: { pending = nil }) {
            VStack(spacing: 16) {
                Image(systemName: isReset ? "exclamationmark.triangle.fill" : "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(tint)
                Text(title).font(.deck(20, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(body).font(.deck(15)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    GhostButton(title: "Cancel", tint: Theme.textSecondary, height: 50) { pending = nil }.frame(maxWidth: .infinity)
                    PrimaryButton(title: confirmLabel, tint: tint, height: 50) {
                        withAnimation {
                            switch action { case .reset: deck.reset(); case .sort(let s): deck.sort(s) }
                        }
                        pending = nil
                    }.frame(maxWidth: .infinity)
                }
            }
            .padding(28).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 22)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        }
    }

    // MARK: Reorder

    private func syncReorderDragging() {
        model.setReorderDragging(editing && !showAdd && !showPageManager)
    }

    private func syncLongPress() {
        model.setLongPressEnabled(!editing && !showAdd && !showPageManager && screenPickerAction == nil)
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
    var pinned: Bool = false
    let onRun: (DeckAction) -> Void

    private var tint: Color {
        switch action.kind {
        case .app: return Theme.accent
        case .url: return Theme.ice
        case .system: return Theme.disk
        case .media: return Theme.memory
        case .command: return Theme.gpu
        case .webhook: return Theme.netUp
        case .keystroke: return Theme.battery
        case .multi: return Theme.heat
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
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(RadialGradient(colors: [tint.opacity(0.14), .clear], center: .top, startRadius: 0, endRadius: 150))
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            )
            .bezel(corner: 20, tint: tint)
            .overlay(alignment: .bottom) {
                if running {
                    Lamp(color: Theme.battery, on: true, size: 6).padding(.bottom, 9)
                }
            }
            // Pinned-to-a-display hint (long-press the tile to change it).
            .overlay(alignment: .topTrailing) {
                if pinned && !editing {
                    Image(systemName: "pin.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.battery).rotationEffect(.degrees(45))
                        .padding(7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
        .opacity(lifted ? 0 : 1)
        .overlay {
            if editing && !lifted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
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
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        } else {
            Image(systemName: action.symbol ?? "app.dashed").font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        }
    }
}

private struct DeckPageManager: View {
    @ObservedObject var deck: DeckStore
    let onClose: () -> Void
    @State private var draft = ""
    @State private var confirmDelete = false

    var body: some View {
        ModalScaffold(onDismiss: onClose) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deck pages").font(.deck(20, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Separate work, media, streaming, or app-specific controls.")
                            .font(.deck(13)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    CircleIconButton(icon: "xmark", size: 42, action: onClose)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(deck.pages) { page in
                            Button {
                                deck.selectPage(page.id)
                                draft = page.name
                                confirmDelete = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: page.id == deck.selectedPageID ? "square.grid.3x3.fill" : "square.grid.3x3")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(page.id == deck.selectedPageID ? Theme.battery : Theme.textFaint)
                                        .frame(width: 28)
                                    Text(page.name).font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(page.actions.count) \(page.actions.count == 1 ? "tile" : "tiles")")
                                        .font(.deck(12)).foregroundStyle(Theme.textFaint)
                                    if page.id == deck.selectedPageID {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.battery)
                                    }
                                }
                                .padding(.horizontal, 14).frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(page.id == deck.selectedPageID ? Theme.battery.opacity(0.11) : Color.white.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(page.id == deck.selectedPageID ? Theme.battery.opacity(0.42) : Theme.stroke, lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }.buttonStyle(.pressable)
                        }
                    }
                }
                .frame(maxHeight: 280)

                HStack(spacing: 10) {
                    DeckField(label: "Selected page name", text: $draft, placeholder: deck.selectedPage.name)
                    Button {
                        deck.renamePage(deck.selectedPageID, to: draft)
                        draft = deck.selectedPage.name
                    } label: {
                        Text("Rename").font(.deck(15, .semibold)).foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 18).frame(height: 48)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.bezelLight, Theme.bezelDark], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 19)
                }

                if confirmDelete {
                    HStack(spacing: 10) {
                        Text("Delete “\(deck.selectedPage.name)” and all its tiles?")
                            .font(.deck(14)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Cancel") { confirmDelete = false }
                            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        Button("Delete") {
                            deck.removePage(deck.selectedPageID)
                            draft = deck.selectedPage.name
                            confirmDelete = false
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.batteryLow)
                    }
                    .frame(minHeight: 44)
                } else {
                    HStack(spacing: 10) {
                        PrimaryButton(title: "New page", icon: "plus", height: 48) {
                            deck.addPage()
                            draft = deck.selectedPage.name
                        }.frame(maxWidth: .infinity)
                        GhostButton(title: "Delete page", icon: "trash",
                                    tint: deck.canRemovePage ? Theme.batteryLow : Theme.textFaint, height: 48) {
                            confirmDelete = true
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(!deck.canRemovePage)
                    }
                }
            }
            .padding(24).frame(width: 680, height: 610)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 24)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
            .onAppear { draft = deck.selectedPage.name }
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
                .foregroundStyle(Theme.strokeStrong))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(.pressable)
    }
}
