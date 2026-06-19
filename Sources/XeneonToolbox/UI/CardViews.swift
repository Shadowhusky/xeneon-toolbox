import SwiftUI
import Charts
import AppKit

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
        case .generic(let title, let rows): GenericCard(title: title, rows: rows)
        case .chart(let title, let points, let line): ChartCard(title: title, points: points, line: line)
        case .table(let title, let headers, let rows): TableCard(title: title, headers: headers, rows: rows)
        case .image(let data): ImageCard(data: data)
        }
    }
}

struct ChartCard: View {
    let title: String
    let points: [ChartPoint]
    let line: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: line ? "chart.xyaxis.line" : "chart.bar.fill").foregroundStyle(Theme.accent)
                Text(title).font(.deck(17, .bold)).foregroundStyle(Theme.textPrimary)
            }
            Chart(points) { p in
                if line {
                    LineMark(x: .value("x", p.label), y: .value("y", p.value))
                        .foregroundStyle(Theme.accent).interpolationMethod(.catmullRom)
                    PointMark(x: .value("x", p.label), y: .value("y", p.value)).foregroundStyle(Theme.accent)
                } else {
                    BarMark(x: .value("x", p.label), y: .value("y", p.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.memory], startPoint: .bottom, endPoint: .top))
                        .cornerRadius(5)
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.stroke); AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .frame(height: 240)
        }
        .padding(20)
        .frame(maxWidth: 900, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}

struct TableCard: View {
    let title: String
    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int { max(headers.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells.fill").foregroundStyle(Theme.accent)
                Text(title).font(.deck(17, .bold)).foregroundStyle(Theme.textPrimary)
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { c in
                        cell(c < headers.count ? headers[c] : "", header: true)
                    }
                }
                .background(Color.white.opacity(0.05))
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { c in
                            cell(c < row.count ? row[c] : "", header: false)
                        }
                    }
                    .background(idx % 2 == 1 ? Color.white.opacity(0.02) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .padding(20)
        .frame(maxWidth: 900, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }

    private func cell(_ text: String, header: Bool) -> some View {
        Text(text)
            .font(header ? .deck(13, .bold) : .deck(14))
            .foregroundStyle(header ? Theme.accent : Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }
}

struct ImageCard: View {
    let data: Data

    var body: some View {
        Group {
            if let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(maxWidth: 520, maxHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            } else {
                Text("Couldn't load image").font(.deck(14)).foregroundStyle(Theme.textFaint)
            }
        }
    }
}

struct GenericCard: View {
    let title: String
    let rows: [CardRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.text.square.fill").foregroundStyle(Theme.accent)
                Text(title).font(.deck(17, .bold)).foregroundStyle(Theme.textPrimary)
            }
            ForEach(rows) { r in
                HStack(alignment: .firstTextBaseline) {
                    Text(r.label).font(.deck(15, .medium)).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 24)
                    Text(r.value).font(.readout(15, .semibold)).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                if r.id != rows.last?.id { Divider().overlay(Theme.stroke) }
            }
        }
        .padding(20)
        .frame(maxWidth: 820, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
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
