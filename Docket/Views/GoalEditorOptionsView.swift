import SwiftUI

struct GoalTimingOptionsView: View {
    @Binding var item: TodoItem
    let isActiveEditor: () -> Bool
    @Environment(\.polarisPalette) private var palette
    private var dated: Bool { item.dueDate != nil }

    var body: some View {
        VStack(spacing: 6) {
            GoalScheduleView(item: $item, isActiveEditor: isActiveEditor)
            HStack(spacing: 10) {
                Toggle("指定时间", isOn: $item.hasDueTime).toggleStyle(.checkbox)
                    .onChange(of: item.hasDueTime) { _, enabled in
                        if enabled, let date = item.dueDate {
                            item.dueDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
                        }
                    }
                Spacer()
                if item.hasDueTime {
                    DatePicker("具体时间", selection: Binding(get: { item.dueDate ?? Date() }, set: { item.dueDate = $0 }), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.field).controlSize(.small)
                        .accessibilityLabel("具体时间")
                } else {
                    Text("全天").foregroundStyle(palette.secondary)
                }
            }.frame(minHeight: 36).disabled(!dated)
            ReminderPickerView(offset: $item.reminderOffset).disabled(!dated)
            if item.hasRemoteRecurrence && item.recurrence == nil {
                HStack {
                    Text("重复由 Apple 提醒事项管理").foregroundStyle(palette.secondary)
                    Spacer()
                    Button("停止重复") { item.remoteRecurrenceRules = nil; item.reminderRecurrenceWasEdited = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }.frame(minHeight: 36)
            } else {
                RecurrencePickerView(
                    hasRecurrence: Binding(get: { item.recurrence != nil }, set: { item.recurrence = $0 ? Recurrence(frequency: item.goalPeriod == .week ? .weekly : .monthly, interval: 1) : nil }),
                    frequency: Binding(get: { item.recurrence?.frequency ?? (item.goalPeriod == .week ? .weekly : .monthly) }, set: { item.recurrence?.frequency = $0 }),
                    interval: Binding(get: { item.recurrence?.interval ?? 1 }, set: { item.recurrence?.interval = $0 }))
                    .disabled(!dated)
            }
            if !dated {
                hint("设定截止日期后，即可使用提醒和重复。")
            } else if !item.hasDueTime, item.reminderOffset != .none {
                hint("按截止日 09:00 计算提醒；当天结束后才算超期。")
            }
        }.font(.system(size: 12.5))
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5)).foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GoalOrganizationView: View {
    @Binding var item: TodoItem
    var store = Store.shared
    @Environment(\.polarisPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.lists.count > 1 {
                HStack(spacing: 12) {
                    Text("目标集").font(.system(size: 12.5)).foregroundStyle(palette.secondary).frame(width: 52, alignment: .leading)
                    Picker("目标集", selection: Binding(get: { item.listId ?? store.activeListId }, set: { item.listId = $0 })) {
                        ForEach(store.lists) { list in Text(list.name).tag(list.id) }
                    }.labelsHidden().pickerStyle(.menu).controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing).accessibilityLabel("目标集")
                }
            }
            PriorityPickerView(priority: $item.priority)
            QuadrantPickerView(quadrant: $item.quadrant)
            LabelPickerView(selectedIds: $item.labelIds, listID: item.listId ?? store.activeListId)
        }
    }
}
