import SwiftUI
import MarkdownUI

/// Renders assistant text as Markdown (GFM: headings, lists, code, tables) with
/// a dark theme tuned to the toolbox palette.
struct MarkdownBubble: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTextStyle {
                ForegroundColor(XeneonToolbox.Theme.textPrimary)
                FontSize(16)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                ForegroundColor(XeneonToolbox.Theme.cpu)
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(14) }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .markdownMargin(top: .em(0.9), bottom: .em(1.1))
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label.markdownMargin(top: .em(0.35), bottom: .em(0.35))
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label.markdownMargin(top: .em(0.2), bottom: .em(0.2))
            }
            .textSelection(.enabled)
    }
}

/// Assistant message bubble: markdown content with a "pop in then settle"
/// highlight on first appearance.
struct AssistantBubble: View {
    let text: String
    @State private var scale = 1.14

    var body: some View {
        HStack {
            MarkdownBubble(text: text.isEmpty ? "…" : text)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06)))
                .frame(maxWidth: 1500, alignment: .leading)
                .scaleEffect(scale, anchor: .leading)
            Spacer(minLength: 80)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { scale = 1.0 }
        }
    }
}
