import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Add-a-tile panel for the Deck: search across apps and actions, pick an installed
/// app, add a website, or build a custom Command / Webhook action with its own icon.
struct AddDeckOverlay: View {
    @ObservedObject var deck: DeckStore
    var onClose: () -> Void

    enum Tab: String, CaseIterable { case apps = "Apps", custom = "Custom", website = "Website", system = "System", media = "Media" }
    @State private var tab: Tab = .apps
    @State private var query = ""
    @State private var apps: [String] = []

    private let cols = [GridItem(.adaptive(minimum: 132, maximum: 160), spacing: 12)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                HStack {
                    Text("Add to Deck").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textSecondary)
                            .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))).contentShape(Circle())
                    }.buttonStyle(.pressable)
                }
                searchField
                if query.isEmpty {
                    tabBar
                    content
                } else {
                    searchResults
                }
            }
            .padding(24)
            .frame(width: 1120, height: 664)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
        }
        .onAppear {
            if apps.isEmpty { apps = DeckStore.installedApps() }
            let env = ProcessInfo.processInfo.environment
            if let t = env["XENEON_DECK_TAB"], let tt = Tab(rawValue: t) { tab = tt }
            if let q = env["XENEON_DECK_QUERY"] { query = q }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textFaint)
            TextField("Search apps and actions", text: $query)
                .textFieldStyle(.plain).font(.deck(16)).foregroundStyle(Theme.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.textFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var candidates: [DeckAction] {
        apps.map { DeckAction.app(path: $0) }
            + DeckSystemAction.allCases.map { DeckAction.system($0) }
            + DeckMediaAction.allCases.map { DeckAction.media($0) }
    }

    private var searchResults: some View {
        let q = query.lowercased()
        let matches = candidates.filter { $0.label.lowercased().contains(q) }
        return Group {
            if matches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
                    Text("No matches for “\(query)”").font(.deck(15)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(matches, id: \.key) { actionCell($0) }
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue).font(.deck(15, .semibold))
                        .foregroundStyle(tab == t ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(tab == t ? Theme.battery.opacity(0.9) : Color.white.opacity(0.05)))
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }.buttonStyle(.pressable)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .apps:
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(apps, id: \.self) { actionCell(.app(path: $0)) }
                }.padding(.vertical, 2)
            }
        case .custom:
            CustomActionForm(deck: deck, onAdded: onClose)
        case .website:
            WebsiteForm(deck: deck, onAdded: onClose)
        case .system:
            actionList(DeckSystemAction.allCases.map { DeckAction.system($0) })
        case .media:
            actionList(DeckMediaAction.allCases.map { DeckAction.media($0) })
        }
    }

    // MARK: Cells

    private func actionCell(_ action: DeckAction) -> some View {
        Button { deck.add(action); onClose() } label: {
            VStack(spacing: 8) {
                DeckActionIcon(action: action, size: 46)
                Text(action.label).font(.deck(12, .medium)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).frame(height: 96)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.pressable)
    }

    private func actionList(_ items: [DeckAction]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(items, id: \.key) { item in
                    Button { deck.add(item); onClose() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol ?? "app.dashed").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.battery).frame(width: 30)
                            Text(item.label).font(.deck(16, .semibold)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 18).frame(height: 60)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.pressable)
                }
            }.frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
    }
}

/// Renders the right icon for any deck action: uploaded image → app icon → SF Symbol.
struct DeckActionIcon: View {
    let action: DeckAction
    var size: CGFloat = 46
    var body: some View {
        if let img = action.customImage {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else if let img = action.appIcon {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: action.symbol ?? "app.dashed").font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Theme.battery).frame(width: size, height: size)
        }
    }
}

/// Labelled text field reused by the website and custom forms.
struct DeckField: View {
    let label: String
    @Binding var text: String
    var placeholder: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.deckLabel).tracking(Theme.labelTracking).foregroundStyle(Theme.textFaint)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.deck(16)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }
}

private struct WebsiteForm: View {
    @ObservedObject var deck: DeckStore
    var onAdded: () -> Void
    @State private var name = ""
    @State private var url = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeckField(label: "Name", text: $name, placeholder: "GitHub")
            DeckField(label: "URL", text: $url, placeholder: "github.com")
            AddButton(enabled: !url.isEmpty) {
                deck.add(.url(url, label: name.isEmpty ? url : name)); onAdded()
            }
            Spacer()
        }
        .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Shared primary "Add to Deck" button.
struct AddButton: View {
    var enabled: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Add to Deck").font(.deck(16, .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(enabled ? Theme.battery : Color.white.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }.buttonStyle(.pressable).disabled(!enabled)
    }
}
