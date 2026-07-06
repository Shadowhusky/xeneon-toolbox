import SwiftUI
import AppKit

/// Edit an existing deck tile: rename, change its icon, and (for websites,
/// commands, webhooks) fix its target. Shown from the deck's edit mode.
struct TileEditForm: View {
    @ObservedObject var deck: DeckStore
    let action: DeckAction
    var onDone: () -> Void

    @State private var label: String
    @State private var target: String
    @State private var symbol: String
    @State private var iconPath: String?

    private let symbols = ["star.fill", "bolt.fill", "globe", "link", "terminal.fill", "bell.fill",
                           "gearshape.fill", "play.fill", "folder.fill", "music.note", "video.fill",
                           "camera.fill", "lock.fill", "flame.fill", "lightbulb.fill", "command",
                           "paperplane.fill", "hammer.fill", "keyboard", "square.grid.2x2.fill"]

    init(deck: DeckStore, action: DeckAction, onDone: @escaping () -> Void) {
        self.deck = deck
        self.action = action
        self.onDone = onDone
        _label = State(initialValue: action.label)
        _target = State(initialValue: action.target)
        _symbol = State(initialValue: action.symbol ?? "star.fill")
        _iconPath = State(initialValue: action.iconPath)
    }

    private var targetLabel: String? {
        switch action.kind {
        case .url: return "URL"
        case .command: return "Command"
        case .webhook: return "Webhook URL"
        default: return nil   // apps/system/media/keystroke/multi keep their target
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: onDone)
            VStack(spacing: 0) {
                HStack {
                    Text("Edit tile").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))).contentShape(Circle())
                    }.buttonStyle(.pressable)
                }
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        DeckField(label: "Label", text: $label, placeholder: action.label)
                        if let t = targetLabel {
                            DeckField(label: t, text: $target, placeholder: action.target)
                        }
                        iconSection
                    }
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                }

                AddButtonLabeled(title: "Save changes", enabled: !label.isEmpty) {
                    deck.update(action.id, label: label,
                                symbol: iconPath == nil ? symbol : nil,
                                iconPath: iconPath,
                                target: targetLabel != nil ? target : nil)
                    onDone()
                }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .padding(24)
            .frame(width: 720, height: 560)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON").font(.deckLabel).tracking(Theme.labelTracking).foregroundStyle(Theme.textFaint)
            HStack(spacing: 14) {
                preview
                Button {
                    if let url = FilePanel.open(contentTypes: [.image], message: "Choose an image for this tile"),
                       let path = DeckStore.importIcon(from: url) { iconPath = path }
                } label: {
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
            if iconPath == nil, action.appIcon == nil {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46, maximum: 58), spacing: 9)], spacing: 9) {
                    ForEach(symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            Image(systemName: s).font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(symbol == s ? .white : Theme.textSecondary)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(symbol == s ? Theme.battery.opacity(0.8) : Color.white.opacity(0.05)))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }.buttonStyle(.pressable)
                    }
                }
            } else if action.appIcon != nil, iconPath == nil {
                Text("This app uses its real icon. Upload an image to override it.")
                    .font(.deck(12)).foregroundStyle(Theme.textFaint)
            }
        }
    }

    private var preview: some View {
        Group {
            if let p = iconPath, let img = NSImage(contentsOfFile: p) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else if let img = action.appIcon {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: 52, height: 52)
            } else {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.battery)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.battery.opacity(0.14)))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// A primary button with a custom title (AddButton reads "Add to Deck").
struct AddButtonLabeled: View {
    var title: String
    var enabled: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.deck(16, .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(enabled ? Theme.battery : Color.white.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }.buttonStyle(.pressable).disabled(!enabled)
    }
}
