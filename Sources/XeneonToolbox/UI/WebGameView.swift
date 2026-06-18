import SwiftUI
import WebKit

/// Embeds a web game in a WKWebView, filling the panel. Used for shanhai and
/// Rhythm Plus — both are full web games that adapt to the Edge.
struct WebGameView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // let game audio start
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url { nsView.load(URLRequest(url: url)) }
    }
}
