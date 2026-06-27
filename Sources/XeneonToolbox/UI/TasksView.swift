import SwiftUI
import ToolboxKit

struct TasksView: View {
    @ObservedObject var todos: TodoStore
    var exportMode = false   // off-screen render: static add bar + non-scrolling list
    @State private var newTitle = ""
    @FocusState private var inputFocused: Bool

    private var open: Int { todos.items.filter { !$0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            addBar
            if todos.items.isEmpty { emptyState } else { list }
        }
        // In export the content is taller than the panel; size to content + let the
        // host top-anchor & clip, so the header stays visible (not centered/clipped).
        .frame(maxWidth: 1500, maxHeight: exportMode ? nil : .infinity, alignment: .top)
        .frame(maxWidth: .infinity, alignment: exportMode ? .top : .center)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
            Text("Tasks").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                if open > 0 { Text("\(open)").font(.readout(15, .bold)).foregroundStyle(Theme.textSecondary) }
                Text(open == 0 ? "All clear" : (open == 1 ? "open" : "open"))
                    .font(.deck(15, .semibold)).foregroundStyle(open == 0 ? Theme.battery : Theme.textSecondary)
            }
            if todos.items.contains(where: { $0.done }) {
                Button("Clear done") { todos.clearCompleted() }
                    .font(.deck(13, .semibold)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .buttonStyle(.pressable)
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.accent)
            if exportMode {
                Text("Add a task… (or ask the assistant to remind you)")
                    .font(.deck(17)).foregroundStyle(Theme.textFaint)
                Spacer()
            } else {
                TextField("Add a task… (or ask the assistant to remind you)", text: $newTitle)
                    .textFieldStyle(.plain).font(.deck(17)).foregroundStyle(Theme.textPrimary)
                    .focused($inputFocused)
                    .onSubmit(add)
                if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: add) {
                        Text("Add").font(.deck(16, .semibold)).foregroundStyle(Theme.background)
                            .padding(.horizontal, 20).frame(height: 44)
                            .background(Capsule().fill(Theme.accent))
                            .deckGlow(Theme.accent, strength: 0.6)
                    }.buttonStyle(.pressable)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .deckRow(tint: Theme.accent, corner: 18)
    }

    private var grouped: [(title: String, color: Color, items: [TodoItem])] {
        let cal = Calendar.current
        var overdue: [TodoItem] = [], today: [TodoItem] = [], upcoming: [TodoItem] = [], anytime: [TodoItem] = [], done: [TodoItem] = []
        for t in todos.sorted {
            if t.done { done.append(t) }
            else if let d = t.dueAt {
                if d < Date() { overdue.append(t) }
                else if cal.isDateInToday(d) { today.append(t) }
                else { upcoming.append(t) }
            } else { anytime.append(t) }
        }
        var out: [(String, Color, [TodoItem])] = []
        if !overdue.isEmpty { out.append(("Overdue", Theme.batteryLow, overdue)) }
        if !today.isEmpty { out.append(("Today", Theme.netUp, today)) }
        if !upcoming.isEmpty { out.append(("Upcoming", Theme.accent, upcoming)) }
        if !anytime.isEmpty { out.append(("Anytime", Theme.textSecondary, anytime)) }
        if !done.isEmpty { out.append(("Done", Theme.textFaint, done)) }
        return out
    }

    @ViewBuilder private var groups: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(grouped, id: \.title) { group in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(group.title.uppercased()).font(.deck(13, .bold)).tracking(1.4).foregroundStyle(group.color)
                        Text("\(group.items.count)").font(.readout(12, .bold)).foregroundStyle(group.color)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(group.color.opacity(0.15)))
                    }
                    .padding(.leading, 4)
                    ForEach(group.items) { item in row(item, tint: group.color) }
                }
            }
        }
        .padding(.vertical, 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos.sorted)
    }

    @ViewBuilder private var list: some View {
        if exportMode { groups } else { ScrollView(showsIndicators: false) { groups } }
    }

    private func row(_ item: TodoItem, tint: Color) -> some View {
        TaskRow(item: item, tint: tint, exportMode: exportMode,
                onToggle: { todos.toggle(item.id) },
                onDelete: { todos.remove(item.id) },
                onSetDue: { todos.update(item.id, dueAt: .some($0)) },
                onSetRecurrence: { todos.update(item.id, recurrence: $0) })
            .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 58, weight: .regular))
                .foregroundStyle(Theme.battery)
                .background(Circle().fill(Theme.battery.opacity(0.16)).frame(width: 108, height: 108).blur(radius: 8))
            Text("Nothing on your list").font(.deck(24, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Add a task above, or say \u{201C}remind me to…\u{201D} in the Assistant.")
                .font(.deck(15)).foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        todos.add(t)
        newTitle = ""
    }
}

/// The layered tile surface, sized for a list row: gradient body, a faint
/// top-anchored accent glow, a hue-tinted hairline, and a soft drop shadow —
/// so rows read as part of the deck, not a flat form.
private struct DeckRow: ViewModifier {
    var tint: Color
    var corner: CGFloat = 16
    var emphasis: Double = 1
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(RadialGradient(colors: [tint.opacity(0.12 * emphasis), .clear],
                                             center: .topLeading, startRadius: 0, endRadius: 320))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [tint.opacity(0.28 * emphasis), Theme.stroke],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

private extension View {
    func deckRow(tint: Color, corner: CGFloat = 16, emphasis: Double = 1) -> some View {
        modifier(DeckRow(tint: tint, corner: corner, emphasis: emphasis))
    }
}

private struct TaskRow: View {
    let item: TodoItem
    var tint: Color = Theme.accent
    var exportMode = false
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onSetDue: (Date?) -> Void
    var onSetRecurrence: (Recurrence) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(item.done ? Theme.battery : (item.isOverdue ? Theme.batteryLow : Theme.textSecondary))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.pressable)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.deck(17, .medium))
                    .foregroundStyle(item.done ? Theme.textFaint : Theme.textPrimary)
                    .strikethrough(item.done, color: Theme.textFaint)
                    .lineLimit(2)
                if let due = item.dueAt { dueChip(due) }
            }
            Spacer(minLength: 12)
            reminderMenu
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textFaint).frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.05)).frame(width: 36, height: 36))
                    .contentShape(Rectangle())
            }.buttonStyle(.pressable)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .deckRow(tint: item.isOverdue ? Theme.batteryLow : tint, emphasis: item.isOverdue ? 1.6 : 1)
        .opacity(item.done ? 0.6 : 1)
    }

    @ViewBuilder private var reminderMenu: some View {
        if exportMode {
            bell
        } else {
            Menu {
                Button("In 1 hour") { onSetDue(Date().addingTimeInterval(3600)) }
                Button("In 3 hours") { onSetDue(Date().addingTimeInterval(3 * 3600)) }
                Button("This evening · 6 PM") { onSetDue(Self.at(18)) }
                Button("Tomorrow · 9 AM") { onSetDue(Self.at(9, tomorrow: true)) }
                if item.dueAt != nil {
                    Menu("Repeat") {
                        Button("Daily") { onSetRecurrence(.daily) }
                        Button("Weekly") { onSetRecurrence(.weekly) }
                        if item.recurrence != .none { Button("Don't repeat") { onSetRecurrence(.none) } }
                    }
                    Divider()
                    Button("Clear reminder", role: .destructive) { onSetDue(nil); onSetRecurrence(.none) }
                }
            } label: {
                bell
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private var bell: some View {
        Image(systemName: item.dueAt != nil ? "bell.fill" : "bell")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(item.dueAt != nil ? Theme.netUp : Theme.textFaint)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.05)).frame(width: 36, height: 36))
            .contentShape(Rectangle())
    }

    private static func at(_ hour: Int, tomorrow: Bool = false) -> Date {
        let cal = Calendar.current
        let base = tomorrow ? cal.date(byAdding: .day, value: 1, to: Date())! : Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    private func dueChip(_ due: Date) -> some View {
        let overdue = item.isOverdue
        let color = item.done ? Theme.textFaint : (overdue ? Theme.batteryLow : Theme.netUp)
        let rec = item.recurrence != .none ? " · ↻ \(item.recurrence.rawValue)" : ""
        return HStack(spacing: 5) {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "bell.fill").font(.system(size: 11))
            Text((overdue ? "Overdue · " : "") + Self.fmt(due) + rec).font(.deck(12, .semibold))
        }
        .foregroundStyle(color)
    }

    private static func fmt(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) { f.dateFormat = "'Today' h:mm a" }
        else if cal.isDateInTomorrow(d) { f.dateFormat = "'Tomorrow' h:mm a" }
        else { f.dateFormat = "EEE d MMM, h:mm a" }
        return f.string(from: d)
    }
}
