import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Build a custom deck tile: run a shell command or call a webhook, with a chosen
/// SF Symbol or an uploaded image as its icon.
struct CustomActionForm: View {
    @ObservedObject var deck: DeckStore
    var onAdded: () -> Void

    enum Mode: String, CaseIterable { case command = "Command", webhook = "Webhook" }
    @State private var mode: Mode = .command
    @State private var label = ""
    @State private var command = ""
    @State private var url = ""
    @State private var method = "GET"
    @State private var httpBody = ""
    @State private var symbol = "bolt.fill"
    @State private var iconPath: String?

    private let symbols = ["bolt.fill", "terminal.fill", "globe", "link", "bell.fill", "gearshape.fill",
                           "play.fill", "arrow.clockwise", "command", "paperplane.fill", "lightbulb.fill",
                           "lock.fill", "camera.fill", "folder.fill", "music.note", "video.fill",
                           "star.fill", "flame.fill", "power", "hammer.fill"]

    private var canAdd: Bool {
        !label.isEmpty && (mode == .command ? !command.isEmpty : !url.isEmpty)
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    modeToggle
                    DeckField(label: "Label", text: $label, placeholder: "My Action")
                    if mode == .command {
                        DeckField(label: "Command", text: $command, placeholder: "open -a Music")
                        Text("Runs through /bin/sh on the Mac.").font(.deck(12)).foregroundStyle(Theme.textFaint)
                    } else {
                        DeckField(label: "URL", text: $url, placeholder: "https://hooks.example.com/…")
                        methodToggle
                        if method == "POST" { DeckField(label: "Body (JSON, optional)", text: $httpBody, placeholder: "{ \"key\": \"value\" }") }
                    }
                    iconPicker
                }
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
            // Pinned so it's always reachable regardless of scroll position.
            AddButton(enabled: canAdd) {
                let action: DeckAction = mode == .command
                    ? .command(command, label: label, symbol: symbol, iconPath: iconPath)
                    : .webhook(url, method: method, body: httpBody.isEmpty ? nil : httpBody, label: label, symbol: symbol, iconPath: iconPath)
                deck.add(action); onAdded()
            }
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    Text(m.rawValue).font(.deck(15, .semibold)).foregroundStyle(mode == m ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(mode == m ? Theme.gpu.opacity(0.9) : Color.white.opacity(0.05)))
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }.buttonStyle(.pressable)
            }
        }
    }

    private var methodToggle: some View {
        HStack(spacing: 8) {
            ForEach(["GET", "POST"], id: \.self) { m in
                Button { method = m } label: {
                    Text(m).font(.deck(14, .semibold)).foregroundStyle(method == m ? .white : Theme.textSecondary)
                        .frame(width: 92, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(method == m ? Theme.netUp.opacity(0.85) : Color.white.opacity(0.05)))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.pressable)
            }
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON").font(.deckLabel).tracking(Theme.labelTracking).foregroundStyle(Theme.textFaint)
            HStack(spacing: 14) {
                preview
                Button(action: uploadIcon) {
                    Label("Upload image", systemImage: "square.and.arrow.up")
                        .font(.deck(14, .semibold)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }.buttonStyle(.pressable)
                if iconPath != nil {
                    Button { iconPath = nil } label: {
                        Text("Use a symbol").font(.deck(14, .semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12).frame(height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            if iconPath == nil {
                // A wrapping grid (not a horizontal scroll) so every symbol is
                // reachable — the touch driver can't finger-scroll a horizontal strip.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46, maximum: 58), spacing: 9)], spacing: 9) {
                    ForEach(symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            Image(systemName: s).font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(symbol == s ? .white : Theme.textSecondary)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(symbol == s ? Theme.gpu.opacity(0.8) : Color.white.opacity(0.05)))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }.buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    private var preview: some View {
        Group {
            if let p = iconPath, let img = NSImage(contentsOfFile: p) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.gpu)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.gpu.opacity(0.14)))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func uploadIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose an image for this deck tile"
        if panel.runModal() == .OK, let url = panel.url, let path = DeckStore.importIcon(from: url) {
            iconPath = path
        }
    }
}
