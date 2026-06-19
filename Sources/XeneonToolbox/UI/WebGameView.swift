import SwiftUI
import WebKit

enum WebLoadState: Equatable { case loading, loaded, failed }

/// Embeds a web game in a WKWebView, filling the panel. Used for shanhai and
/// Rhythm Plus — both are full web games that adapt to the Edge. Reports load
/// progress so the host can show a spinner or a retry prompt.
struct WebGameView: NSViewRepresentable {
    let url: URL
    @Binding var state: WebLoadState

    func makeCoordinator() -> Coordinator { Coordinator(state: $state) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // let game audio start
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url { nsView.load(URLRequest(url: url)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: Binding<WebLoadState>
        init(state: Binding<WebLoadState>) { self.state = state }

        private func set(_ s: WebLoadState) { DispatchQueue.main.async { self.state.wrappedValue = s } }
        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { set(.loading) }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { set(.loaded) }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { set(.failed) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { set(.failed) }
    }
}
