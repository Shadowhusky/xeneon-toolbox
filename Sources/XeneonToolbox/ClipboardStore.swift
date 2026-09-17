import AppKit
import ToolboxKit

/// Watches the pasteboard for the Clipboard tile. In-memory only — nothing is
/// written to disk — and items a password manager marks as concealed are skipped.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var history = ClipboardHistory(capacity: 8)
    @Published var paused = false

    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let maxLength = 4000

    func start() {
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount
        // changeCount is a cheap integer read; the string is fetched only on change.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard !paused, !(pb.types ?? []).contains(Self.concealed),
              let s = pb.string(forType: .string), s.count <= Self.maxLength else { return }
        history.push(s)
    }

    func copyBack(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChange = pb.changeCount
        history.push(text)
    }

    func remove(at index: Int) { history.remove(at: index) }
    func clear() { history.removeAll() }
}
