import SwiftUI

/// Watches one permission while it's on screen: polls once a second (the checks
/// are cheap) so the moment the user flips the switch in System Settings, the
/// card notices, tells them, and hands back to the feature.
@MainActor
final class PermissionWatcher: ObservableObject {
    let permission: AppPermission
    @Published private(set) var status: AppPermission.Status
    @Published private(set) var awaitingSettings = false
    private var timer: Timer?
    var onGranted: (() -> Void)?

    init(_ permission: AppPermission) {
        self.permission = permission
        status = permission.status
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func guide() {
        awaitingSettings = true
        permission.guide()
    }

    private func refresh() {
        let now = permission.status
        guard now != status else { return }
        status = now
        if now == .granted {
            awaitingSettings = false
            AppLog.info("permissions", "\(permission.title) granted")
            onGranted?()
        }
    }
}

/// An inline "this needs permission" card for tiles and panels: one button does
/// the whole trip and the card confirms when access arrives.
struct PermissionGuide: View {
    @StateObject private var watcher: PermissionWatcher
    private let onGranted: () -> Void
    var compact = false

    init(_ permission: AppPermission, compact: Bool = false, onGranted: @escaping () -> Void = {}) {
        _watcher = StateObject(wrappedValue: PermissionWatcher(permission))
        self.compact = compact
        self.onGranted = onGranted
    }

    var body: some View {
        let p = watcher.permission
        VStack(spacing: compact ? 10 : 14) {
            Image(systemName: p.icon).font(.system(size: compact ? 24 : 30, weight: .semibold))
                .foregroundStyle(watcher.status == .granted ? Theme.battery : Theme.accent)
            VStack(spacing: 4) {
                Text(watcher.status == .granted ? "\(p.title) allowed" : p.askTitle)
                    .font(.deck(compact ? 14 : 16, .semibold)).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(hint).font(.deck(compact ? 12 : 13)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if watcher.status != .granted {
                PrimaryButton(title: buttonTitle, icon: watcher.status == .denied ? "arrow.up.forward.app" : "checkmark.shield",
                              height: 44) { watcher.guide() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .onAppear { watcher.onGranted = onGranted; watcher.start() }
        .onDisappear { watcher.stop() }
        .animation(Motion.smooth, value: watcher.status)
    }

    private var buttonTitle: String {
        watcher.status == .denied ? "Open System Settings" : "Allow"
    }

    private var hint: String {
        switch watcher.status {
        case .granted: return "All set."
        case .denied:
            return watcher.awaitingSettings
                ? "Turn on Xeneon Toolbox in the list on your main display. This card updates by itself."
                : watcher.permission.purpose
        case .notDetermined: return watcher.permission.purpose
        }
    }
}

/// The Settings hub: every permission with a live lamp and the one-tap trip.
struct PermissionsList: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(AppPermission.allCases) { PermissionRow(permission: $0) }
        }
    }
}

private struct PermissionRow: View {
    @StateObject private var watcher: PermissionWatcher

    init(permission: AppPermission) {
        _watcher = StateObject(wrappedValue: PermissionWatcher(permission))
    }

    var body: some View {
        let p = watcher.permission
        HStack(spacing: 12) {
            Image(systemName: p.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.badgeCorner, style: .continuous).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title).font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(p.purpose).font(.deck(12)).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                Lamp(color: tint, on: true, size: 7)
                Text(label).font(.deck(12, .semibold)).foregroundStyle(tint)
            }
            if watcher.status != .granted {
                GhostButton(title: watcher.status == .denied ? "Open Settings" : "Allow", tint: Theme.textPrimary, height: 40) {
                    watcher.guide()
                }
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: Theme.wellCorner, style: .continuous).fill(Color.white.opacity(0.04)))
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
        .animation(Motion.smooth, value: watcher.status)
    }

    private var tint: Color {
        switch watcher.status {
        case .granted: return Theme.battery
        case .denied: return Theme.critical
        case .notDetermined: return Theme.warning
        }
    }

    private var label: String {
        switch watcher.status {
        case .granted: return "Allowed"
        case .denied: return "Off"
        case .notDetermined: return "Not asked"
        }
    }
}
