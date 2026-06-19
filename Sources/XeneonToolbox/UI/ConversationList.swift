import SwiftUI

struct ConversationList: View {
    @ObservedObject var agent: AgentController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { agent.newConversation() } } label: {
                Label("New chat", systemImage: "plus.circle.fill")
                    .font(.deck(15, .semibold)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.14)))
            }
            .buttonStyle(.pressable)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(agent.conversations) { c in row(c) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .disabled(agent.busy)
        .opacity(agent.busy ? 0.55 : 1)
    }

    private func row(_ c: StoredConversation) -> some View {
        let active = c.id == agent.activeID
        return HStack(spacing: 9) {
            Image(systemName: "bubble.left.fill").font(.system(size: 11))
                .foregroundStyle(active ? Theme.accent : Theme.textFaint)
            Text(c.title.isEmpty ? "New chat" : c.title)
                .font(.deck(14, active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            if agent.conversations.count > 1 {
                Button { withAnimation { agent.delete(c.id) } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Color.white.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { agent.select(c.id) } }
    }
}
