// TaskDetailView.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

/// Edit view for an existing task with reminder settings.
struct TaskDetailView: View {
    @State var item: TodoItem
    @Binding var path: [NavDestination]
    @State private var hasDueDate = false
    @State private var hasRecurrence = false
    @State private var recurrenceFreq: Frequency = .weekly
    @State private var recurrenceInterval: Int = 1
    @State private var naturalDateText = ""
    @State private var parsedDatePreview: String? = nil
    @State private var originalItem: TodoItem?

    @AppStorage("appTheme") private var themeRaw: Int = AppTheme.white.rawValue
    @AppStorage("customHue") private var customHue: Double = 0.55
    private var accent: Color { ThemeManager.resolvedAccent(themeRaw: themeRaw, customHue: customHue) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VScroll {
                VStack(spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(L10n.titleFieldPlaceholder, text: $item.title)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.medium))
                        Rectangle().fill(accent.opacity(0.15)).frame(height: 1.5)
                    }

                    // Notes
                    TextField(L10n.notesPlaceholder, text: $item.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2...4)

                    // Priority + Labels
                    VStack(alignment: .leading, spacing: 14) {
                        PriorityPickerView(priority: $item.priority)
                        LabelPickerView(selectedIds: $item.labelIds)
                        QuadrantPickerView(quadrant: $item.quadrant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Due date
                    VStack(alignment: .leading, spacing: 10) {
                        ThemedToggle(label: L10n.dueDate, isOn: $hasDueDate, animated: true)
                        if hasDueDate {
                            // Natural language input
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundStyle(accent)
                                TextField(L10n.smartDatePlaceholder, text: $naturalDateText)
                                    .textFieldStyle(.plain)
                                    .font(.subheadline)
                                    .onSubmit { parseNaturalDate() }
                                    .onChange(of: naturalDateText) { _, _ in parseNaturalDate() }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(accent.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.15), lineWidth: 1))
                            )

                            if let parsed = parsedDatePreview {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right").font(.system(size: 9))
                                    Text(parsed).font(.caption)
                                }
                                .foregroundStyle(accent)
                                .padding(.leading, 4)
                            }

                            CalendarPickerView(selectedDate: Binding(
                                get: { item.dueDate ?? Date().addingTimeInterval(3600) },
                                set: { item.dueDate = $0 }
                            ))
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            TimePickerView(date: Binding(
                                get: { item.dueDate ?? Date().addingTimeInterval(3600) },
                                set: { item.dueDate = $0 }
                            ))
                            ReminderPickerView(offset: $item.reminderOffset)
                            RecurrencePickerView(hasRecurrence: $hasRecurrence, frequency: $recurrenceFreq, interval: $recurrenceInterval)
                        }
                    }

                    // Move to list
                    if Store.shared.lists.count > 1 {
                        HStack {
                            Text(L10n.list).font(.body)
                            Spacer()
                            Menu {
                                ForEach(Store.shared.lists) { list in
                                    Button(list.name) { item.listId = list.id }
                                }
                            } label: {
                                Text(Store.shared.lists.first(where: { $0.id == item.listId })?.name ?? "—")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.12)))
                                    .foregroundStyle(accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Meta
                    HStack {
                        Text(L10n.created).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.tertiary)
                    }

                    // Delete
                    Button {
                        Store.shared.delete(item)
                        if !path.isEmpty { path.removeLast() }
                    } label: {
                        Text(L10n.deleteTask)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
        }
        .onAppear {
            originalItem = item
            hasDueDate = item.dueDate != nil
            hasRecurrence = item.recurrence != nil
            recurrenceFreq = item.recurrence?.frequency ?? .weekly
            recurrenceInterval = item.recurrence?.interval ?? 1
        }
        .onChange(of: hasDueDate) { _, on in
            if !on { item.dueDate = nil }
            else if item.dueDate == nil { item.dueDate = Date().addingTimeInterval(3600) }
        }
    }

    private var header: some View {
        HStack {
            Button { cancelEdit() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.quaternary.opacity(0.5)))
            }.buttonStyle(.plain)
            Spacer()
            Text(L10n.editTask).font(.headline)
            Spacer()
            Button { confirmEdit() } label: { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).frame(width: 28, height: 28).background(Circle().fill(.quaternary.opacity(0.5))) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

    }

    private func confirmEdit() {
        // Trim and reject a title that would render as empty. Cheaper than
        // failing at the store layer and keeps the user in-context with the
        // (unsaved) edits visible.
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.title = trimmed
        item.recurrence = hasDueDate && hasRecurrence ? Recurrence(frequency: recurrenceFreq, interval: recurrenceInterval, endDate: nil) : nil

        // Skip a no-op update — spares Reminders sync a round trip and
        // avoids re-scheduling identical notifications.
        if let original = originalItem, original == item {
            if !path.isEmpty { path.removeLast() }
            return
        }

        // Moving between lists is handled entirely by Store.update — it
        // cleans up labels that don't belong to the destination list and
        // assigns a collision-free sortOrder. No pre-work needed here.
        Store.shared.update(item)
        if !path.isEmpty { path.removeLast() }
    }

    private func cancelEdit() {
        // Cancel means *discard*: do not write the original back. The store
        // was never mutated during editing (this view holds a local `@State`
        // copy), so simply dropping our copy is correct — writing the
        // original would needlessly reschedule notifications and re-push to
        // Reminders when the user explicitly asked to abandon changes.
        if !path.isEmpty { path.removeLast() }
    }

    private func parseNaturalDate() {
        if let date = DateParser.parse(naturalDateText) {
            item.dueDate = date
            parsedDatePreview = date.formatted(date: .abbreviated, time: .shortened)
        } else {
            parsedDatePreview = nil
        }
    }
}
