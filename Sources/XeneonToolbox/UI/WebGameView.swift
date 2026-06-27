import SwiftUI
import WebKit

enum WebLoadState: Equatable { case loading, loaded, failed }

/// A WKWebView that actively takes keyboard focus, so key-driven web games
/// (Rhythm Plus) receive keystrokes instead of letting them fall through the
/// responder chain unhandled — which is what makes macOS beep on every keypress.
final class GameWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        grabFocus()
    }

    override func mouseDown(with event: NSEvent) {
        grabFocus()
        super.mouseDown(with: event)
    }

    func grabFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            window.makeFirstResponder(self)
        }
    }
}

/// Embeds a web game in a WKWebView, filling the panel. Reports load progress so
/// the host can show a spinner or a retry prompt.
struct WebGameView: NSViewRepresentable {
    let url: URL
    @Binding var state: WebLoadState

    func makeCoordinator() -> Coordinator { Coordinator(state: $state) }

    func makeNSView(context: Context) -> GameWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // let game audio start
        let web = GameWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: GameWebView, context: Context) {
        if nsView.url != url { nsView.load(URLRequest(url: url)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: Binding<WebLoadState>
        init(state: Binding<WebLoadState>) { self.state = state }

        private func set(_ s: WebLoadState) { DispatchQueue.main.async { self.state.wrappedValue = s } }
        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { set(.loading) }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            set(.loaded)
            (w as? GameWebView)?.grabFocus()   // focus once the game is ready for keys
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { set(.failed) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { set(.failed) }
    }
}
