import SwiftUI

/// "Open on which screen?" for an app: its open windows (tap to raise, or arm
/// one and pick a screen to move it there), Chrome profiles / New Window, the
/// displays (tap to open there, pin to always open there), and Quit. Used by
/// the Deck's long-press and the dashboard's Running-apps tile.
struct ScreenPickerOverlay: View {
    let model: ToolboxModel
    @ObservedObject var deck: DeckStore
    let action: DeckAction
    let running: Bool
    var onClose: () -> Void

    /// Select-then-place: a window/profile/new-window row is "armed", and the
    /// screen buttons become its placement targets.
    enum ArmedSession: Equatable {
        case window(id: Int, title: String)
        case profile(ChromeProfiles.Profile)
        case newWindow

        var label: String {
            switch self {
            case .window(_, let t): return t
            case .profile(let p): return "New window · \(p.name)"
            case .newWindow: return "New window"
            }
        }
    }
    @State private var armed: ArmedSession?

    var body: some View {
        let displays = WindowMover.displays()
        let currentName = running ? WindowMover.currentDisplayName(appPath: action.target) : nil
        let windows = running ? WindowMover.windows(appPath: action.target) : []
        let profiles = ChromeProfiles.profiles(appPath: action.target)
        // Read the live tile so the pin state reflects edits made in this modal;
        // apps that aren't deck tiles (the Running tile) can't be pinned.
        let onDeck = deck.actions.contains { $0.id == action.id }
        let pinned = (deck.actions.first { $0.id == action.id } ?? action).preferredDisplay
        let hasLeft = running || !profiles.isEmpty
        return ModalScaffold(onDismiss: onClose) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    DeckActionIcon(action: action, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label).font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                        if let a = armed {
                            Text("Now tap a screen to place: \(a.label)")
                                .font(.deck(13, .semibold)).foregroundStyle(Theme.battery)
                                .lineLimit(1).truncationMode(.middle)
                        } else {
                            Text(running ? "Switch a window, open a new one, or move it to a screen"
                                         : (onDeck ? "Open on a screen · pin one to always open there" : "Open on a screen"))
                                .font(.deck(13)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 14) {
                    if hasLeft {
                        VStack(spacing: 10) {
                            if !windows.isEmpty {
                                pickerLabel("Windows")
                                ScrollView(showsIndicators: false) {
                                    VStack(spacing: 8) {
                                        ForEach(windows) { w in windowRow(w) }
                                    }
                                }
                                .frame(maxHeight: windows.count > 3 ? 172 : .infinity)
                                .fixedSize(horizontal: false, vertical: windows.count <= 3)
                            }
                            if !profiles.isEmpty {
                                pickerLabel(windows.isEmpty ? "Profiles" : "New window as")
                                ForEach(profiles) { p in profileRow(p) }
                            }
                            if running && profiles.isEmpty { newWindowRow }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    VStack(spacing: 10) {
                        pickerLabel(armed != nil ? "Place on" : (running ? "Move to" : "Open on"))
                        ForEach(displays) { d in
                            displayRow(d, pinned: pinned == d.name, current: currentName == d.name, pinnable: onDeck, windows: windows)
                        }
                        if running && !profiles.isEmpty { newWindowRow }
                        if running { quitRow }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(24).frame(width: hasLeft ? 980 : 520)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.tileBottom.opacity(0.85)))
            .bezel(corner: 22)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        }
        .onAppear {
            // Headless check of select-then-place: "<tile label>|<screen name>"
            // arms the first window of this app and places it after 3s.
            if let spec = ProcessInfo.processInfo.environment["XENEON_TEST_PLACE"] {
                let parts = spec.split(separator: "|").map(String.init)
                guard parts.count == 2, parts[0] == action.label else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let windows = WindowMover.windows(appPath: action.target)
                    guard let w = windows.first, let d = WindowMover.displays().first(where: { $0.name == parts[1] }) else {
                        AppLog.error("deck", "TEST_PLACE: no window or screen for \(spec)"); return
                    }
                    armed = .window(id: w.id, title: w.title)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        executeArmed(.window(id: w.id, title: w.title), on: d, windows: windows)
                    }
                }
            }
        }
    }

    private func pickerLabel(_ s: String) -> some View {
        Text(s).font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One of the app's open windows — tap to bring exactly it to the front;
    /// tap the screen glyph to arm it, then pick a screen to move it there.
    private func windowRow(_ w: WindowMover.AppWindow) -> some View {
        sessionRow(icon: "macwindow", tint: Theme.accent, title: w.title,
                   trailing: "arrow.up.forward",
                   isArmed: armed == .window(id: w.id, title: w.title),
                   mainAction: { WindowMover.raise(w, appPath: action.target); onClose() },
                   armAs: .window(id: w.id, title: w.title))
    }

    /// A Chromium browser profile ("user") — tap to focus-or-open that profile's
    /// window; arm it to choose which screen the new window lands on.
    private func profileRow(_ p: ChromeProfiles.Profile) -> some View {
        sessionRow(icon: "person.crop.circle", tint: Theme.memory, title: p.name,
                   trailing: "plus.square.on.square",
                   isArmed: armed == .profile(p),
                   mainAction: { ChromeProfiles.open(appPath: action.target, profileDir: p.dir); onClose() },
                   armAs: .profile(p))
    }

    /// Generic "New Window" (activate + ⌘N); arm it to place the new window.
    private var newWindowRow: some View {
        sessionRow(icon: "plus.rectangle.on.rectangle", tint: Theme.accent, title: "New window",
                   trailing: nil,
                   isArmed: armed == .newWindow,
                   mainAction: { WindowMover.openNewWindow(appPath: action.target); onClose() },
                   armAs: .newWindow)
    }

    /// A session row: the body runs the default action; the trailing screen
    /// glyph arms select-then-place (tap a screen next to put it there).
    private func sessionRow(icon: String, tint: Color, title: String, trailing: String?,
                            isArmed: Bool, mainAction: @escaping () -> Void, armAs: ArmedSession) -> some View {
        HStack(spacing: 8) {
            Button(action: mainAction) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint).frame(width: 26)
                    Text(title).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let trailing {
                        Image(systemName: trailing).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(.horizontal, 14).frame(height: 52).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isArmed ? Theme.battery.opacity(0.12) : tint.opacity(tint == Theme.memory ? 0.08 : 0.03)))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isArmed ? Theme.battery.opacity(0.55) : Theme.stroke, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }.buttonStyle(.pressable)
            // Arm toggle: "send to a screen…"
            Button {
                withAnimation(Motion.snappy) { armed = isArmed ? nil : armAs }
            } label: {
                Image(systemName: isArmed ? "display.and.arrow.down" : "display")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isArmed ? Theme.battery : Theme.textFaint)
                    .frame(width: 48, height: 52)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isArmed ? Theme.battery.opacity(0.14) : Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(isArmed ? Theme.battery.opacity(0.55) : Theme.stroke, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }.buttonStyle(.pressable)
        }
    }

    /// Carry out a select-then-place: put the armed window (or the window the
    /// armed action is about to create) on the chosen display.
    private func executeArmed(_ a: ArmedSession, on d: WindowMover.Display, windows: [WindowMover.AppWindow]) {
        if d.isEdge { model.hideToBadge() }
        switch a {
        case .window(let id, let title):
            if let w = windows.first(where: { $0.title == title }) ?? windows.first(where: { $0.id == id }) {
                WindowMover.move(w, appPath: action.target, to: d)
            }
        case .profile(let p):
            ChromeProfiles.open(appPath: action.target, profileDir: p.dir)
            WindowMover.placeUpcomingWindow(appPath: action.target, on: d, before: windows)
        case .newWindow:
            WindowMover.openNewWindow(appPath: action.target)
            // ⌘N fires ~0.45s after activation — start watching a beat later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                WindowMover.placeUpcomingWindow(appPath: action.target, on: d, before: windows)
            }
        }
        armed = nil
        onClose()
    }

    private func displayRow(_ d: WindowMover.Display, pinned: Bool, current: Bool, pinnable: Bool,
                            windows: [WindowMover.AppWindow]) -> some View {
        let placing = armed != nil
        let tint = placing ? Theme.battery : (pinned ? Theme.battery : Theme.accent)
        // Choosing the Edge hands the screen over: the panel collapses into the
        // floating badge and the app opens where the Toolbox was.
        let subtitle = placing ? (d.isEdge ? "Place here · Toolbox hides to badge" : "Place here")
            : current ? "Currently here"
            : pinned ? "Always opens here"
            : d.isEdge ? "Toolbox hides into the badge"
            : "\(Int(d.bounds.width))×\(Int(d.bounds.height))"
        return HStack(spacing: 10) {
            // Tap the row body → place the armed session here, or open the app.
            Button {
                if let a = armed {
                    executeArmed(a, on: d, windows: windows)
                } else {
                    if d.isEdge { model.hideToBadge() }
                    WindowMover.open(appPath: action.target, on: d)
                    onClose()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: d.isEdge ? "rectangle.bottomthird.inset.filled" : "display")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint).frame(width: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .font(.deck(12))
                            .foregroundStyle(placing || current || pinned ? Theme.battery : Theme.textFaint)
                    }
                    Spacer(minLength: 0)
                    if current {
                        Circle().fill(Theme.battery).frame(width: 7, height: 7).deckGlow(Theme.battery, strength: 0.8)
                    }
                    Image(systemName: "arrow.up.forward").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 16).frame(height: 60).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(placing ? Theme.battery.opacity(0.10) : pinned ? Theme.battery.opacity(0.12) : Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(placing ? Theme.battery.opacity(0.6) : pinned ? Theme.battery.opacity(0.5) : Theme.stroke, lineWidth: placing ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.buttonStyle(.pressable)
            // Pin toggle → make this the tile's default (tap opens here from now on).
            if pinnable {
                Button {
                    withAnimation(Motion.snappy) { deck.setPreferredDisplay(action.id, pinned ? nil : d.name) }
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pinned ? Theme.battery : Theme.textFaint)
                        .frame(width: 54, height: 60)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pinned ? Theme.battery.opacity(0.12) : Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pinned ? Theme.battery.opacity(0.5) : Theme.stroke, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.pressable)
            }
        }
    }

    private var quitRow: some View {
        Button {
            WindowMover.quit(appPath: action.target)
            onClose()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.batteryLow).frame(width: 30)
                Text("Quit \(action.label)").font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(height: 60).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.batteryLow.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.batteryLow.opacity(0.4), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.pressable)
    }
}
