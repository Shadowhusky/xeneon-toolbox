import SwiftUI

/// Shows the agent's tool activity live (spinner on the running step), then
/// collapses to a minimal chip once everything's done.
struct ToolStepsView: View {
    let steps: [ToolStep]
    @State private var expanded = false
    private var working: Bool { steps.contains { !$0.done } }

    var body: some View {
        Group {
            if working {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { s in
                        HStack(spacing: 8) {
                            if s.done {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.battery)
                            } else {
                                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14)
                            }
                            Text(s.text).font(.deck(13, .medium))
                                .foregroundStyle(s.done ? Theme.textFaint : Theme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 11))
                            Text(steps.count == 1 ? steps.first!.text : "\(steps.count) steps")
                                .font(.deck(13, .medium))
                            if steps.count > 1 {
                                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                            }
                        }
                        .foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    if expanded && steps.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(steps) { s in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.battery)
                                    Text(s.text).font(.deck(12)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .padding(.leading, 14)
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: working)
    }
}

/// Renders a generative-UI card the agent produced into the transcript.
struct AgentCardView: View {
    let card: AgentCard

    var body: some View {
        switch card {
        case .processes(let rows): ProcessCard(rows: rows)
        }
    }
}

struct ProcessCard: View {
    let rows: [ProcRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill").foregroundStyle(Theme.cpu)
                Text("Top Processes").font(.deck(17, .bold)).foregroundStyle(Theme.textPrimary)
            }
            ForEach(rows) { r in
                HStack(spacing: 14) {
                    Text(r.name).font(.deck(15, .medium)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).frame(width: 220, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [Theme.cpu.opacity(0.7), Theme.cpu], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, g.size.width * min(1, r.cpu / 100)))
                        }
                    }
                    .frame(height: 12)
                    Text("\(Int(r.cpu))%").font(.readout(15, .bold)).foregroundStyle(Theme.cpu).frame(width: 56, alignment: .trailing)
                    Text("\(Int(r.mem))% mem").font(.deck(12)).foregroundStyle(Theme.textFaint).frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 820, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cpu.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}
