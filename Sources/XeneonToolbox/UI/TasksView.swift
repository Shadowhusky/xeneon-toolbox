import SwiftUI
import ToolboxKit

struct TasksView: View {
    @ObservedObject var todos: TodoStore
    @State private var newTitle = ""
    @FocusState private var inputFocused: Bool

    private var open: Int { todos.items.filter { !$0.done }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            addBar
            if todos.items.isEmpty { emptyState } else { list }
        }
        .frame(maxWidth: 1200, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
            Text("Tasks").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(open == 0 ? "All clear" : "\(open) open")
                .font(.deck(15, .semibold)).foregroundStyle(open == 0 ? Theme.battery : Theme.textSecondary)
            if todos.items.contains(where: { $0.done }) {
                Button("Clear done") { todos.clearCompleted() }
                    .font(.deck(13, .semibold)).foregroundStyle(Theme.textFaint).buttonStyle(.plain)
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.accent)
            TextField("Add a task… (or ask the assistant to remind you)", text: $newTitle)
                .textFieldStyle(.plain).font(.deck(17)).foregroundStyle(Theme.textPrimary)
                .focused($inputFocused)
                .onSubmit(add)
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: add) {
                    Text("Add").font(.deck(15, .semibold)).foregroundStyle(Theme.background)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }.buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(todos.sorted) { item in
                    TaskRow(item: item,
                            onToggle: { todos.toggle(item.id) },
                            onDelete: { todos.remove(item.id) },
                            onSetDue: { todos.update(item.id, dueAt: .some($0)) },
                            onSetRecurrence: { todos.update(item.id, recurrence: $0) })
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.vertical, 2)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: todos.sorted)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 52, weight: .light)).foregroundStyle(Theme.textFaint)
            Text("Nothing on your list").font(.deck(20, .semibold)).foregroundStyle(Theme.textSecondary)
            Text("Add a task above, or say \u{201C}remind me to…\u{201D} in the Assistant.")
                .font(.deck(14)).foregroundStyle(Theme.textFaint)
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

private struct TaskRow: View {
    let item: TodoItem
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
            }.buttonStyle(.pressable)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.deck(17, .medium))
                    .foregroundStyle(item.done ? Theme.textFaint : Theme.textPrimary)
                    .strikethrough(item.done, color: Theme.textFaint)
                    .lineLimit(2)
                if let due = item.dueAt {
                    dueChip(due)
                }
            }
            Spacer(minLength: 12)
            reminderMenu
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textFaint).frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.05)))
            }.buttonStyle(.pressable)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(item.isOverdue ? Theme.batteryLow.opacity(0.10) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(item.isOverdue ? Theme.batteryLow.opacity(0.4) : Theme.stroke, lineWidth: 1))
        .opacity(item.done ? 0.65 : 1)
    }

    private var reminderMenu: some View {
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
            Image(systemName: item.dueAt != nil ? "bell.fill" : "bell")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.dueAt != nil ? Theme.netUp : Theme.textFaint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.05)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
