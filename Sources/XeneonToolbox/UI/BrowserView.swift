import SwiftUI
import WebKit

/// Drives a single WKWebView for the Web tab: exposes navigation state to SwiftUI
/// (back/forward/loading/progress/title/url) and normalizes free-text input into
/// a URL or a web search. Reuses GameWebView so keyboard-driven pages get focus.
final class WebController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let wk: GameWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var failed = false
    @Published var progress: Double = 0
    @Published var pageTitle = ""
    @Published var currentURLString = ""
    @Published var showingHome = true   // persisted with the session so the page survives tab switches
    private var lastRequested: URL?
    private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        wk = GameWebView(frame: .zero, configuration: config)
        super.init()
        wk.navigationDelegate = self
        wk.uiDelegate = self
        wk.setValue(false, forKey: "drawsBackground")
        wk.allowsBackForwardNavigationGestures = true
        wk.allowsMagnification = true   // enables pinch-to-zoom (driver maps pinch → ⌘-scroll)

        func sync(_ block: @escaping () -> Void) { DispatchQueue.main.async(execute: block) }
        observers = [
            wk.observe(\.canGoBack, options: [.initial, .new]) { [weak self] w, _ in sync { self?.canGoBack = w.canGoBack } },
            wk.observe(\.canGoForward, options: [.initial, .new]) { [weak self] w, _ in sync { self?.canGoForward = w.canGoForward } },
            wk.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in sync { self?.progress = w.estimatedProgress } },
            wk.observe(\.title, options: [.new]) { [weak self] w, _ in sync { self?.pageTitle = w.title ?? "" } },
            wk.observe(\.url, options: [.new]) { [weak self] w, _ in sync { self?.currentURLString = w.url?.absoluteString ?? "" } },
        ]
    }

    func load(_ raw: String) {
        guard let url = WebController.normalize(raw) else { return }
        lastRequested = url
        failed = false
        showingHome = false
        wk.load(URLRequest(url: url))
    }

    func goBack() { if wk.canGoBack { wk.goBack() } }
    func goForward() { if wk.canGoForward { wk.goForward() } }

    /// Reload the page the user is actually on. On a provisional failure nothing
    /// commits, so `wk.reload()` would no-op (first load) or reload a stale page;
    /// re-issue the last requested URL instead unless it's already committed.
    func reload() {
        failed = false
        if let last = lastRequested {
            if wk.url == last { wk.reload() } else { wk.load(URLRequest(url: last)) }
        } else if wk.url != nil {
            wk.reload()
        }
    }

    // stopLoading() during the provisional phase fires no "finished" callback (or a
    // cancelled error we ignore), so clear the loading state here or it sticks on.
    func stop() { wk.stopLoading(); isLoading = false; progress = 0 }

    /// A scheme'd URL, a bare domain promoted to https, or a Google search.
    static func normalize(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), let scheme = u.scheme, scheme == "http" || scheme == "https" { return u }
        if s.contains(".") && !s.contains(" ") {
            return URL(string: "https://\(s)")
        }
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: s)]
        return c.url
    }

    /// The site's real favicon via Google's favicon service (handles redirects to
    /// the actual icon for most domains).
    static func faviconURL(_ urlString: String, size: Int = 128) -> URL? {
        guard let host = URL(string: urlString)?.host ?? URL(string: "https://\(urlString)")?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=\(size)&domain=\(host)")
    }

    // Open target=_blank / window.open in the same view rather than dropping it.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }

    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { isLoading = true; failed = false }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { isLoading = false; (w as? GameWebView)?.grabFocus() }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { isLoading = false; failed = true }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        // Ignore the "cancelled" error that fires when a new load interrupts one.
        if (e as NSError).code == NSURLErrorCancelled { return }
        isLoading = false; failed = true
    }
}

struct WebPageView: NSViewRepresentable {
    let controller: WebController
    func makeNSView(context: Context) -> GameWebView { controller.wk }
    func updateNSView(_ nsView: GameWebView, context: Context) {}
}

/// The in-app browser. It's no longer a nav tab of its own — you reach it by tapping
/// a website tile on the Deck (which is now the single place websites live). It's a
/// focused viewer: toolbar + page, with a grid button back to the Deck and a "+" that
/// saves the current page onto the Deck as a website tile.
struct BrowserView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var web: WebController
    @State private var address = ""
    @State private var saved = false
    @FocusState private var addressFocused: Bool

    private let accent = AppRoute.web.accent

    var body: some View {
        VStack(spacing: 0) {
            if !model.fullscreen { toolbar }
            ZStack {
                WebPageView(controller: web)
                if web.isLoading { progressBar }
                if web.failed { errorOverlay }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: model.fullscreen ? 0 : Theme.tileCorner, style: .continuous))
            .overlay {
                if !model.fullscreen {
                    RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [accent.opacity(0.22), Theme.stroke],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .padding(.top, model.fullscreen ? 0 : 12)
        }
        .onAppear {
            if address.isEmpty, !web.currentURLString.isEmpty { address = web.currentURLString }
            if let u = model.pendingWebURL { open(u); model.pendingWebURL = nil }
            else if web.currentURLString.isEmpty { model.route = .deck }   // nothing to show → the launcher
        }
        .onChange(of: model.pendingWebURL) { if let u = model.pendingWebURL { open(u); model.pendingWebURL = nil } }
        .onChange(of: web.currentURLString) {
            if !addressFocused, !web.currentURLString.isEmpty { address = web.currentURLString }
            saved = false
        }
        .animation(.easeInOut(duration: 0.2), value: web.failed)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            iconButton("square.grid.3x3.fill") { model.route = .deck }   // back to the Deck launcher
            iconButton("chevron.left", enabled: web.canGoBack) { web.goBack() }
            iconButton("chevron.right", enabled: web.canGoForward) { web.goForward() }
            iconButton(web.isLoading ? "xmark" : "arrow.clockwise") { web.isLoading ? web.stop() : web.reload() }

            addressField

            iconButton(saved ? "checkmark" : "plus", enabled: !web.currentURLString.isEmpty, active: saved) { saveCurrent() }
            // The toolbar only renders when not fullscreen, so this always enters it.
            iconButton("arrow.up.left.and.arrow.down.right") { model.toggleFullscreen() }
        }
        .padding(.horizontal, 2)
    }

    private var addressField: some View {
        HStack(spacing: 9) {
            Image(systemName: web.failed ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(web.failed ? Theme.critical : Theme.textFaint)
            TextField("Search or enter address", text: $address)
                .textFieldStyle(.plain)
                .font(.deck(16, .medium))
                .foregroundStyle(Theme.textPrimary)
                .focused($addressFocused)
                .onSubmit { submitAddress() }
            if !address.isEmpty && addressFocused {
                Button { address = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(addressFocused ? accent.opacity(0.7) : Theme.strokeStrong, lineWidth: 1))
    }

    // MARK: - Overlays

    private var progressBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Rectangle().fill(accent)
                    .frame(width: max(0, geo.size.width * web.progress))
                    .deckGlow(accent, strength: 0.7)
            }
            .frame(height: 3)
            Spacer()
        }
    }

    private var errorOverlay: some View {
        ZStack {
            LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.critical).deckGlow(Theme.critical, strength: 0.6)
                Text("Couldn't load the page").font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                Text("Check the address and your connection.").font(.deck(14)).foregroundStyle(Theme.textFaint)
                HStack(spacing: 12) {
                    Button { web.reload() } label: {
                        Label("Retry", systemImage: "arrow.clockwise").font(.deck(16, .semibold)).foregroundStyle(accent)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Capsule().fill(accent.opacity(0.16)))
                    }.buttonStyle(.pressable)
                    Button { model.route = .deck } label: {
                        Label("Deck", systemImage: "square.grid.3x3.fill").font(.deck(16, .semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }.buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: - Actions

    private func open(_ urlString: String) {
        address = urlString
        web.load(urlString)
    }

    private func submitAddress() {
        let t = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        web.load(t)
    }

    /// Save the current page onto the Deck as a website tile (deduped by canonical URL).
    private func saveCurrent() {
        let target = web.currentURLString
        guard !target.isEmpty else { return }
        let key = WebAppStore.canonicalKey(target)
        if !model.deck.actions.contains(where: { $0.kind == .url && WebAppStore.canonicalKey($0.target) == key }) {
            model.deck.add(.url(target, label: web.pageTitle.isEmpty ? WebAppStore.displayName(target) : web.pageTitle))
        }
        saved = true
    }

    // MARK: - Small components

    private func iconButton(_ name: String, enabled: Bool = true, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(active ? accent : (enabled ? Theme.textPrimary : Theme.textFaint.opacity(0.5)))
                .frame(width: 48, height: 48)
                .background(Circle().fill(active ? accent.opacity(0.16) : Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}
