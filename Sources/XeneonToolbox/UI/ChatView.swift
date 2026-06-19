import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ToolboxKit

struct ChatView: View {
    @ObservedObject var model: ToolboxModel
    @ObservedObject var agent: AgentController
    @State private var config: ChatConfig?
    @State private var showSettings: Bool
    @State private var input = ""
    @State private var pendingImageURL: URL?
    @State private var pendingImageName: String?

    init(model: ToolboxModel) {
        _model = ObservedObject(wrappedValue: model)
        _agent = ObservedObject(wrappedValue: model.agent)
        let saved = ChatConfig.loadSaved()
        _config = State(initialValue: saved)
        _showSettings = State(initialValue: saved == nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            ConversationList(agent: agent)
            mainColumn.padding(.leading, 18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if let p = ProcessInfo.processInfo.environment["XENEON_AGENT_PROMPT"],
               config != nil, agent.turns.isEmpty {
                agent.send(text: p, imageDataURL: nil)
            }
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if showSettings || config == nil {
                ChatSettingsView(initial: config) { saved in
                    saved.save(); config = saved; agent.update(config: saved); showSettings = false
                } cancel: {
                    if config != nil { showSettings = false }
                }
            } else if model.exportMode {
                exportTranscript
                inputBar
            } else {
                transcript
                if let p = agent.pending {
                    confirmBanner(p).transition(.move(edge: .bottom).combined(with: .opacity))
                }
                inputBar
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: agent.pending?.id)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accent)
            Text("Assistant").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            if let c = config, !showSettings {
                Label("\(c.model) · \(host(c))", systemImage: "server.rack")
                    .font(.deck(13, .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary).frame(width: 50, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ImageRenderer doesn't lay out ScrollView content off-screen; a plain stack does.
    private var exportTranscript: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(agent.turns) { t in bubble(t) }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if agent.turns.isEmpty { emptyState }
                    ForEach(agent.turns) { t in bubble(t).id(t.id) }
                    if agent.busy { dots }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            .onChange(of: agent.turns.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: agent.turns.last?.text) { _, _ in scrollToEnd(proxy) }
            .onChange(of: agent.busy) { _, _ in scrollToEnd(proxy) }
            .onChange(of: agent.activeID) { _, _ in scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy) }
        }
        .frame(maxHeight: .infinity)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
        }
    }

    private struct Suggestion { let icon: String; let label: String; let prompt: String }
    private let suggestions: [Suggestion] = [
        .init(icon: "gauge.with.dots.needle.67percent", label: "How's my system?",
              prompt: "How's my system doing right now? Summarize CPU, memory and disk."),
        .init(icon: "list.bullet.rectangle.fill", label: "Top processes", prompt: "Show my top processes"),
        .init(icon: "tablecells.fill", label: "Compare GPUs",
              prompt: "Make a table comparing the RTX 4090, RTX 4080 Super, and RX 7900 XTX by VRAM, TDP, and price"),
        .init(icon: "magnifyingglass", label: "Latest AI news",
              prompt: "Search the web for the latest AI news and summarize the top items"),
        .init(icon: "gamecontroller.fill", label: "Open the card game", prompt: "Open the card game"),
        .init(icon: "music.note", label: "What's playing?", prompt: "What's playing right now?"),
    ]

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask anything — or tell me to drive the app").font(.deck(20, .semibold)).foregroundStyle(Theme.textSecondary)
                Text("Tap a suggestion to start, or attach an image.").font(.deck(14)).foregroundStyle(Theme.textFaint)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(suggestions, id: \.prompt) { s in suggestionChip(s) }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private func suggestionChip(_ s: Suggestion) -> some View {
        Button { sendPrompt(s.prompt) } label: {
            HStack(spacing: 10) {
                Image(systemName: s.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 22)
                Text(s.label).font(.deck(15, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(agent.busy || config == nil)
    }

    @ViewBuilder private func bubble(_ t: Turn) -> some View {
        switch t.role {
        case "tools":
            ToolStepsView(steps: t.steps)
        case "assistant":
            AssistantBubble(text: t.text)
        case "card":
            if let card = t.card {
                HStack { AgentCardView(card: card); Spacer(minLength: 40) }
            }
        default:
            let isUser = t.role == "user", isError = t.role == "error"
            HStack {
                if isUser { Spacer(minLength: 80) }
                VStack(alignment: .leading, spacing: 6) {
                    if t.imageThumb {
                        Label("Image attached", systemImage: "photo").font(.deck(12)).foregroundStyle(Theme.textFaint)
                    }
                    Text(t.text.isEmpty ? "…" : t.text)
                        .font(.deck(16)).foregroundStyle(isError ? Theme.batteryLow : Theme.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? Theme.accent.opacity(0.22) : Color.white.opacity(0.06)))
                .frame(maxWidth: 1500, alignment: isUser ? .trailing : .leading)
                if !isUser { Spacer(minLength: 80) }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("…").font(.deck(14)).foregroundStyle(Theme.textFaint)
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = pendingImageName {
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill").foregroundStyle(Theme.accent)
                    Text(name).font(.deck(13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Button { pendingImageURL = nil; pendingImageName = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            HStack(spacing: 12) {
                Button(action: pickImage) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 24))
                        .foregroundStyle(Theme.textSecondary).frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                }.buttonStyle(.plain)
                Group {
                    if model.exportMode {
                        // ImageRenderer renders live TextFields poorly; use a static pill for mockups.
                        HStack { Text("Message the assistant…").foregroundStyle(Theme.textFaint); Spacer() }
                            .font(.deck(17))
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                    } else {
                        TextField("Message the assistant…", text: $input)
                            .textFieldStyle(.plain).font(.deck(17))
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                            .onSubmit(send)
                    }
                }
                Button(action: agent.busy ? agent.cancel : send) {
                    Image(systemName: agent.busy ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(agent.busy ? Theme.batteryLow : (canSend ? Theme.accent : Theme.textFaint))
                }.buttonStyle(.plain).disabled(!agent.busy && !canSend)
            }
        }
    }

    private func confirmBanner(_ p: AgentController.PendingAction) -> some View {
        let accent = p.dangerous ? Theme.batteryLow : Theme.netUp
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: p.dangerous ? "exclamationmark.triangle.fill" : "exclamationmark.shield.fill").foregroundStyle(accent)
                Text("Approve: \(p.title)?").font(.deck(16, .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(p.detail).font(.system(size: 14, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                .lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                pill("Approve", fg: Theme.background, bg: accent) { agent.resolve(.approve) }
                if !p.dangerous { pill("Always allow", fg: Theme.accent, bg: Theme.accent.opacity(0.2)) { agent.resolve(.always) } }
                pill("Deny", fg: Theme.textSecondary, bg: Color.white.opacity(0.08)) { agent.resolve(.deny) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.4), lineWidth: 1))
    }

    private func pill(_ title: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.deck(15, .semibold)).foregroundStyle(fg)
                .padding(.horizontal, 22).padding(.vertical, 12).background(Capsule().fill(bg))
        }.buttonStyle(.plain)
    }

    private var canSend: Bool {
        (!input.trimmingCharacters(in: .whitespaces).isEmpty || pendingImageURL != nil) && !agent.busy && config != nil
    }
    private func host(_ c: ChatConfig) -> String { URL(string: c.baseURL)?.host ?? "local" }

    private func sendPrompt(_ text: String) {
        guard !agent.busy, config != nil else { return }
        agent.send(text: text, imageDataURL: nil)
    }

    private func send() {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || pendingImageURL != nil), !agent.busy, config != nil else { return }
        if text.isEmpty, pendingImageURL != nil { text = "What's in this image?" }
        input = ""
        agent.send(text: text, imageDataURL: pendingImageURL)
        pendingImageURL = nil; pendingImageName = nil
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        pendingImageURL = URL(string: "data:\(mime);base64,\(data.base64EncodedString())")
        pendingImageName = url.lastPathComponent
    }
}

private struct ChatSettingsView: View {
    let initial: ChatConfig?
    let onSave: (ChatConfig) -> Void
    let cancel: () -> Void

    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var models: [String] = []
    @State private var detecting = false

    init(initial: ChatConfig?, onSave: @escaping (ChatConfig) -> Void, cancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.cancel = cancel
        _baseURL = State(initialValue: initial?.baseURL ?? "")
        _model = State(initialValue: initial?.model ?? "")
        _apiKey = State(initialValue: initial?.apiKey ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up your assistant").font(.deck(20, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Pick a provider, or enter any OpenAI-compatible endpoint (local models included).")
                .font(.deck(14)).foregroundStyle(Theme.textFaint)
            HStack(spacing: 12) {
                ForEach(ChatConfig.presets, id: \.name) { preset in
                    Button {
                        baseURL = preset.config.baseURL; model = preset.config.model; detect()
                    } label: {
                        Text(preset.name).font(.deck(15, .semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    }.buttonStyle(.plain)
                }
            }
            field("Endpoint", text: $baseURL, placeholder: "http://localhost:11434/v1")
            modelRow
            field("API key (optional for local)", text: $apiKey, placeholder: "sk-…", secure: true)
            HStack(spacing: 12) {
                Button {
                    onSave(ChatConfig(baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                                      model: model.trimmingCharacters(in: .whitespaces),
                                      apiKey: apiKey.isEmpty ? nil : apiKey,
                                      systemPrompt: nil))
                } label: {
                    Text("Save").font(.deck(17, .semibold)).foregroundStyle(Theme.background)
                        .padding(.horizontal, 32).padding(.vertical, 13)
                        .background(Capsule().fill(canSave ? Theme.accent : Theme.textFaint))
                }.buttonStyle(.plain).disabled(!canSave)
                if initial != nil {
                    Button(action: cancel) {
                        Text("Cancel").font(.deck(17, .medium)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 24).padding(.vertical, 13)
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MODEL").font(.deck(11, .bold)).tracking(1.2).foregroundStyle(Theme.textFaint)
                Spacer()
                Button(action: detect) {
                    HStack(spacing: 6) {
                        if detecting { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                        Text(detecting ? "Detecting…" : "Detect").font(.deck(12, .semibold))
                    }.foregroundStyle(Theme.accent)
                }.buttonStyle(.plain).disabled(detecting)
            }
            if models.isEmpty {
                TextField("llama3.2 / gpt-4o-mini", text: $model)
                    .textFieldStyle(.plain).font(.deck(16)).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            } else {
                Menu {
                    ForEach(models, id: \.self) { m in Button(m) { model = m } }
                } label: {
                    HStack {
                        Text(model.isEmpty ? "Select a model" : model)
                            .foregroundStyle(model.isEmpty ? Theme.textFaint : Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down").foregroundStyle(Theme.textSecondary)
                    }
                    .font(.deck(16)).padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                }.menuStyle(.borderlessButton)
            }
        }
    }

    private func detect() {
        detecting = true
        let url = baseURL, key = apiKey
        Task {
            let found = await ChatClient.listModels(baseURL: url, apiKey: key.isEmpty ? nil : key)
            await MainActor.run {
                models = found
                if let first = found.first, !found.contains(model) { model = first }
                detecting = false
            }
        }
    }

    private var canSave: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.deck(11, .bold)).tracking(1.2).foregroundStyle(Theme.textFaint)
            Group {
                if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
            }
            .textFieldStyle(.plain).font(.deck(16)).foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}

typealias Turn = AgentController.Turn
