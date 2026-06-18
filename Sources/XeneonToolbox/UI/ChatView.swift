import SwiftUI
import ToolboxKit

private struct Turn: Identifiable {
    let id = UUID()
    let role: String   // "user" | "assistant" | "error"
    var text: String
}

struct ChatView: View {
    @State private var config: ChatConfig? = ChatConfig.loadSaved()
    @State private var showSettings = ChatConfig.loadSaved() == nil
    @State private var turns: [Turn] = []
    @State private var input = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if showSettings || config == nil {
                ChatSettingsView(initial: config) { saved in
                    saved.save(); config = saved; showSettings = false
                } cancel: {
                    if config != nil { showSettings = false }
                }
            } else {
                transcript
                inputBar
            }
        }
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
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 50, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(turns) { t in bubble(t).id(t.id) }
                    if sending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.deck(14)).foregroundStyle(Theme.textFaint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func bubble(_ t: Turn) -> some View {
        let isUser = t.role == "user", isError = t.role == "error"
        return HStack {
            if isUser { Spacer(minLength: 80) }
            Text(t.text)
                .font(.deck(16)).foregroundStyle(isError ? Theme.batteryLow : Theme.textPrimary)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? Theme.accent.opacity(0.22) : Color.white.opacity(0.06)))
                .frame(maxWidth: 1400, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 80) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message the assistant…", text: $input)
                .textFieldStyle(.plain).font(.deck(17))
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 36))
                    .foregroundStyle(canSend ? Theme.accent : Theme.textFaint)
            }
            .buttonStyle(.plain).disabled(!canSend)
        }
    }

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespaces).isEmpty && !sending && config != nil }
    private func host(_ c: ChatConfig) -> String { URL(string: c.baseURL)?.host ?? "local" }

    private func send() {
        guard let config else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        turns.append(Turn(role: "user", text: text))
        sending = true
        let history = turns.filter { $0.role != "error" }.map { (role: $0.role, content: $0.text) }
        let client = ChatClient(config: config)
        Task {
            do {
                let reply = try await client.reply(to: history)
                await MainActor.run { turns.append(Turn(role: "assistant", text: reply)); sending = false }
            } catch {
                await MainActor.run {
                    turns.append(Turn(role: "error", text: "⚠️ \(error.localizedDescription)")); sending = false
                }
            }
        }
    }
}

private struct ChatSettingsView: View {
    let initial: ChatConfig?
    let onSave: (ChatConfig) -> Void
    let cancel: () -> Void

    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String

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
            Text("Set up your assistant")
                .font(.deck(20, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Pick a provider, or enter any OpenAI-compatible endpoint (local models included).")
                .font(.deck(14)).foregroundStyle(Theme.textFaint)

            HStack(spacing: 12) {
                ForEach(ChatConfig.presets, id: \.name) { preset in
                    Button {
                        baseURL = preset.config.baseURL; model = preset.config.model
                    } label: {
                        Text(preset.name).font(.deck(15, .semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }

            field("Endpoint", text: $baseURL, placeholder: "http://localhost:11434/v1")
            field("Model", text: $model, placeholder: "llama3.2 / gpt-4o-mini")
            field("API key (optional for local)", text: $apiKey, placeholder: "sk-…", secure: true)

            HStack(spacing: 12) {
                Button {
                    onSave(ChatConfig(baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                                      model: model.trimmingCharacters(in: .whitespaces),
                                      apiKey: apiKey.isEmpty ? nil : apiKey,
                                      systemPrompt: "You are a concise, helpful assistant on a compact touchscreen."))
                } label: {
                    Text("Save").font(.deck(17, .semibold)).foregroundStyle(Theme.background)
                        .padding(.horizontal, 32).padding(.vertical, 13)
                        .background(Capsule().fill(canSave ? Theme.accent : Theme.textFaint))
                }
                .buttonStyle(.plain).disabled(!canSave)
                if initial != nil {
                    Button(action: cancel) {
                        Text("Cancel").font(.deck(17, .medium)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 24).padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: 760, alignment: .leading)
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
