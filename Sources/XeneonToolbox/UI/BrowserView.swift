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
    static func faviconURL(_ urlString: String) -> URL? {
        guard let host = URL(string: urlString)?.host ?? URL(string: "https://\(urlString)")?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
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

struct BrowserView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var store: WebAppStore
    @ObservedObject var web: WebController
    @State private var address = ""
    @State private var editing = false
    @State private var showAdd = false
    @FocusState private var addressFocused: Bool

    private let accent = AppRoute.web.accent

    var body: some View {
        VStack(spacing: 0) {
            if !model.fullscreen { toolbar }
            ZStack {
                WebPageView(controller: web)
                    .opacity(web.showingHome ? 0 : 1)
                if web.isLoading && !web.showingHome { progressBar }
                if web.failed && !web.showingHome { errorOverlay }
                if web.showingHome { homeLauncher }
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
        }
        .onChange(of: model.pendingWebURL) { if let u = model.pendingWebURL { open(u); model.pendingWebURL = nil } }
        .onChange(of: web.currentURLString) { if !addressFocused, !web.currentURLString.isEmpty { address = web.currentURLString } }
        .animation(.easeInOut(duration: 0.25), value: web.showingHome)
        .animation(.easeInOut(duration: 0.2), value: web.failed)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            iconButton("chevron.left", enabled: web.canGoBack && !web.showingHome) { web.goBack() }
            iconButton("chevron.right", enabled: web.canGoForward && !web.showingHome) { web.goForward() }
            iconButton(web.isLoading ? "xmark" : "arrow.clockwise", enabled: !web.showingHome) {
                web.isLoading ? web.stop() : web.reload()
            }
            iconButton("square.grid.2x2", enabled: !web.showingHome, active: false) { goHome() }

            addressField

            iconButton("plus", enabled: !web.showingHome && !web.currentURLString.isEmpty) { saveCurrent() }
            // The toolbar only renders when not fullscreen, so this always enters it.
            iconButton("arrow.up.left.and.arrow.down.right") { model.toggleFullscreen() }
        }
        .padding(.horizontal, 2)
    }

    private var addressField: some View {
        HStack(spacing: 9) {
            Image(systemName: web.failed ? "exclamationmark.triangle.fill" : (web.showingHome ? "magnifyingglass" : "lock.fill"))
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

    // MARK: - Home launcher

    private var homeLauncher: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                HStack {
                    Text("Saved sites").font(.deck(20, .bold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if !store.apps.isEmpty {
                        textPill(editing ? "Done" : "Edit") { editing.toggle() }
                    }
                    textPill("Add", icon: "plus") { showAdd = true; editing = false }
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)

                if showAdd { addRow }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14)], spacing: 14) {
                        ForEach(store.apps) { app in siteTile(app) }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 22)
                }
                if store.apps.isEmpty && !showAdd { emptyState }
            }
        }
    }

    private func siteTile(_ app: WebApp) -> some View {
        Button { open(app.urlString) } label: {
            HStack(spacing: 14) {
                avatar(app)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.title).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(WebAppStore.displayName(app.urlString)).font(.deck(12)).foregroundStyle(Theme.textFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(height: 84)
            .background(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button { store.remove(app.id) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(Theme.critical)
                            .background(Circle().fill(.black).padding(3))
                    }
                    .buttonStyle(.plain).offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Name (optional)", text: $newName)
                .textFieldStyle(.plain).font(.deck(15)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).frame(width: 220, height: 46)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
            TextField("https://example.com", text: $newURL)
                .textFieldStyle(.plain).font(.deck(15)).foregroundStyle(Theme.textPrimary)
                .onSubmit { commitAdd() }
                .padding(.horizontal, 14).frame(height: 46).frame(maxWidth: .infinity)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
            textPill("Save", icon: "checkmark") { commitAdd() }
            textPill("Cancel") { showAdd = false; newName = ""; newURL = "" }
        }
        .padding(.horizontal, 22).padding(.bottom, 14)
    }

    @State private var newName = ""
    @State private var newURL = ""

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "globe").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.textFaint)
            Text("No saved sites yet").font(.deck(16, .medium)).foregroundStyle(Theme.textSecondary)
            Text("Tap Add, or type an address above.").font(.deck(13)).foregroundStyle(Theme.textFaint)
            Spacer()
        }
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
                    Button { goHome() } label: {
                        Label("Home", systemImage: "square.grid.2x2").font(.deck(16, .semibold)).foregroundStyle(Theme.textSecondary)
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
        web.showingHome = false
        editing = false
    }

    private func submitAddress() {
        let t = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        web.load(t)
        web.showingHome = false
    }

    private func goHome() { web.showingHome = true }

    private func saveCurrent() {
        guard !web.currentURLString.isEmpty else { return }
        store.add(title: web.pageTitle, urlString: web.currentURLString)
    }

    private func commitAdd() {
        guard store.add(title: newName, urlString: WebController.normalize(newURL)?.absoluteString ?? newURL) != nil else { return }
        newName = ""; newURL = ""; showAdd = false
    }

    // MARK: - Small components

    private func avatar(_ app: WebApp) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
            .frame(width: 52, height: 52)
            .overlay {
                if let u = WebController.faviconURL(app.urlString) {
                    AsyncImage(url: u) { phase in
                        if let img = phase.image {
                            img.resizable().interpolation(.high).scaledToFit().frame(width: 30, height: 30)
                        } else {
                            letterMark(app.title)
                        }
                    }
                } else {
                    letterMark(app.title)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func letterMark(_ title: String) -> some View {
        let letter = String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        // Stable per-title hue (hashValue is randomized per process, so derive our own).
        let seed = title.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        // Use the unsigned bit pattern — abs(Int.min) would trap.
        let hue = Double(UInt(bitPattern: seed) % 360) / 360
        return Text(letter.isEmpty ? "?" : letter)
            .font(.deck(22, .bold)).foregroundStyle(Color(hue: hue, saturation: 0.55, brightness: 0.95))
    }

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

    private func textPill(_ label: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(label).font(.deck(14, .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16).frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
