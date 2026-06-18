import SwiftUI
import WebKit

/// Embeds Rhythm Plus (https://v2.rhythm-plus.com) — a polished open web rhythm
/// game — in a WKWebView, adapted to fill the Edge. Minimal integration: load
/// the hosted game; the page is responsive so it fits the panel.
struct RhythmWebView: NSViewRepresentable {
    let url = URL(string: "https://v2.rhythm-plus.com/")!

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // allow game audio to start
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct RhythmView: View {
    @State private var reloadID = UUID()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RhythmWebView()
                .id(reloadID)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button { reloadID = UUID() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}
