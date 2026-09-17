import AppKit

/// The regular apps currently running — the dashboard's Dock tile. Driven by
/// workspace notifications (launch, quit, activation); nothing polls.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    struct App: Identifiable, Equatable {
        let id: pid_t
        let name: String
        let path: String
        let isActive: Bool
    }

    @Published private(set) var apps: [App] = []
    private var observers: [NSObjectProtocol] = []
    private static let iconCache = NSCache<NSString, NSImage>()

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let list = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && $0.bundleURL != nil }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
            .map { App(id: $0.processIdentifier, name: $0.localizedName ?? "App",
                       path: $0.bundleURL?.path ?? "", isActive: $0.processIdentifier == front) }
        if list != apps { apps = list }
    }

    static func icon(for app: App) -> NSImage {
        if let hit = iconCache.object(forKey: app.path as NSString) { return hit }
        let img = NSWorkspace.shared.icon(forFile: app.path)
        img.size = NSSize(width: 64, height: 64)
        iconCache.setObject(img, forKey: app.path as NSString)
        return img
    }

    /// Bring the app forward on the main display (never over the Edge).
    func activate(_ app: App) {
        WindowMover.openOffEdge(appPath: app.path)
    }
}
