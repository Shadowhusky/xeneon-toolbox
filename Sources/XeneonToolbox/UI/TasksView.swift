import SwiftUI
import ToolboxKit

struct TasksView: View {
    @ObservedObject var todos: TodoStore
    var exportMode = false   // off-screen render: static add bar + non-scrolling list
    @State private var newTitle = ""
    @FocusState private var inputFocused: Bool
    @State private var dueEditor: TodoItem?

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
        // Custom "pick date & time" reminder — hoisted here so it isn't clipped by
        // the task list's ScrollView.
        .overlay {
            if let item = dueEditor {
                DueDatePicker(initial: item.dueAt ?? Self.defaultDue,
                              onSet: { todos.update(item.id, dueAt: .some($0)); dueEditor = nil },
                              onClose: { dueEditor = nil })
            }
        }
        .animation(Motion.pop, value: dueEditor)
    }

    /// A sensible starting point for a fresh custom reminder: the next round hour.
    private static var defaultDue: Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: cal.component(.hour, from: next), minute: 0, second: 0, of: next) ?? next
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accent)
            Text("Tasks").font(.deck(28, .bold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                if open > 0 { Text("\(open)").font(.readout(15, .bold)).foregroundStyle(Theme.textSecondary) }
                Text(open == 0 ? "All clear" : "open")
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
        .animation(Motion.standard, value: todos.sorted)
    }

    @ViewBuilder private var list: some View {
        if exportMode { groups } else { ScrollView(showsIndicators: false) { groups } }
    }

    private func row(_ item: TodoItem, tint: Color) -> some View {
        TaskRow(item: item, tint: tint, exportMode: exportMode,
                onToggle: { todos.toggle(item.id) },
                onDelete: { todos.remove(item.id) },
                onSetDue: { todos.update(item.id, dueAt: .some($0)) },
                onSetRecurrence: { todos.update(item.id, recurrence: $0) },
                onRename: { todos.update(item.id, title: $0) },
                onPickCustomDue: { dueEditor = item })
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
    var onRename: (String) -> Void = { _ in }
    var onPickCustomDue: () -> Void = {}

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(item.done ? Theme.battery : (item.isOverdue ? Theme.batteryLow : Theme.textSecondary))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.pressable)

            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    TextField("Task", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.deck(17, .medium)).foregroundStyle(Theme.textPrimary)
                        .focused($fieldFocused)
                        .onSubmit(commitEdit)
                        .onChange(of: fieldFocused) { if !fieldFocused { commitEdit() } }
                } else {
                    // Tap the title to rename in place — the whole model supports it,
                    // so a typo no longer means delete-and-re-add.
                    Text(item.title)
                        .font(.deck(17, .medium))
                        .foregroundStyle(item.done ? Theme.textFaint : Theme.textPrimary)
                        .strikethrough(item.done, color: Theme.textFaint)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture { if !exportMode { beginEdit() } }
                }
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

    private func beginEdit() {
        draft = item.title
        editing = true
        fieldFocused = true
    }

    private func commitEdit() {
        guard editing else { return }   // onSubmit + blur can both fire; save once
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != item.title { onRename(trimmed) }
    }

    @ViewBuilder private var reminderMenu: some View {
        if exportMode {
            bell
        } else {
            Menu {
                Button("In 1 hour") { onSetDue(Date().addingTimeInterval(3600)) }
                Button("In 3 hours") { onSetDue(Date().addingTimeInterval(3 * 3600)) }
                // Only offer "this evening" while 6 PM is still ahead — past it the
                // reminder would be instantly overdue and never fire.
                if Self.at(18) > Date() {
                    Button("This evening · 6 PM") { onSetDue(Self.at(18)) }
                }
                Button("Tomorrow · 9 AM") { onSetDue(Self.at(9, tomorrow: true)) }
                Divider()
                Button("Pick date & time…") { onPickCustomDue() }
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

/// A touch-friendly date + time picker for a custom reminder, in the app's modal
/// style. Only lets you pick a time in the future (a past reminder never fires).
private struct DueDatePicker: View {
    @State var date: Date
    let onSet: (Date) -> Void
    let onClose: () -> Void

    init(initial: Date, onSet: @escaping (Date) -> Void, onClose: @escaping () -> Void) {
        _date = State(initialValue: initial)
        self.onSet = onSet
        self.onClose = onClose
    }

    var body: some View {
        ModalScaffold(onDismiss: onClose) {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.netUp)
                    Text("Remind me").font(.deck(22, .bold)).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
                DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.netUp)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Text("Cancel").font(.deck(16, .semibold)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.buttonStyle(.pressable)
                    Button { onSet(date) } label: {
                        Text("Set reminder").font(.deck(16, .bold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.netUp))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }.buttonStyle(.pressable)
                }
            }
            .padding(26).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
        }
    }
}
