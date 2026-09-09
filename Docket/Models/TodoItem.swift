// TodoItem.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

// MARK: - Priority

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low = 0, medium = 1, high = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low: L10n.priorityLow
        case .medium: L10n.priorityMedium
        case .high: L10n.priorityHigh
        }
    }

    /// Pastel color used consistently across task cards, the priority picker,
    /// and the matrix pills. Centralized here so the three call sites can't drift.
    var color: Color {
        switch self {
        case .low:    Color(red: 0.45, green: 0.72, blue: 0.95)
        case .medium: Color(red: 0.95, green: 0.75, blue: 0.40)
        case .high:   Color(red: 0.95, green: 0.50, blue: 0.55)
        }
    }
}

/// Lossless public EventKit rule fields. Unknown UI patterns remain Apple-owned.
/// No calendar-item IDs or account credentials are stored in this value.
struct ReminderRecurrenceRule: Codable, Hashable {
    struct Weekday: Codable, Hashable { var day: Int; var week: Int }
    var frequency: Int
    var interval: Int
    var calendarIdentifier: String?
    var weekdays: [Weekday]
    var monthDays: [Int]
    var months: [Int]
    var weeks: [Int]
    var yearDays: [Int]
    var positions: [Int]
    var endDate: Date?
    var occurrenceCount: Int

    var simpleRecurrence: Recurrence? {
        guard let frequency = Frequency(rawValue: frequency), interval > 0,
              calendarIdentifier == nil || calendarIdentifier == "gregorian",
              weekdays.isEmpty, monthDays.isEmpty, months.isEmpty,
              weeks.isEmpty, yearDays.isEmpty, positions.isEmpty, occurrenceCount == 0 else { return nil }
        return Recurrence(frequency: frequency, interval: interval, endDate: endDate)
    }
}

// MARK: - TodoItem

/// A local step within a goal. It is independent of the goal's completion state.
struct GoalStep: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false

    static func normalized(_ steps: [GoalStep]) -> [GoalStep] {
        var ids = Set<UUID>()
        return steps.compactMap { step in
            var value = step
            value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.title.isEmpty else { return nil }
            if !ids.insert(value.id).inserted { value.id = UUID(); ids.insert(value.id) }
            return value
        }
    }

    func forNextOccurrence() -> GoalStep { GoalStep(title: title) }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var steps: [GoalStep]
    var createdAt: Date
    var completedAt: Date?
    var priorityRaw: Int
    var dueDate: Date?
    var reminderOffsetRaw: Int
    var sortOrder: Int
    var listId: UUID?
    var labelIds: [UUID]
    var recurrence: Recurrence?
    var reminderId: String?
    var lastSyncedAt: Date?
    var quadrant: Quadrant?
    var matrixX: Double?
    var matrixY: Double?
    var isPinned: Bool
    var goalPeriod: GoalPeriod
    var hasDueTime: Bool
    // Optional additions keep existing files and exports decodable without migration.
    var localModifiedAt: Date?
    var reminderCalendarId: String?
    var reminderDueTimeZoneID: String?
    var remoteRecurrenceRules: [ReminderRecurrenceRule]?
    var reminderRecurrenceWasEdited: Bool?
    var spawnedRecurrenceID: UUID?
    var recurrenceParentID: UUID?

    var hasRemoteRecurrence: Bool { remoteRecurrenceRules?.isEmpty == false }

    // MARK: Computed Properties

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var reminderOffset: ReminderOffset {
        get { ReminderOffset(rawValue: reminderOffsetRaw) ?? .tenMinutes }
        set { reminderOffsetRaw = newValue.rawValue }
    }

    var isCompleted: Bool { completedAt != nil }

    var isOverdue: Bool {
        isOverdue(at: Date())
    }

    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let due = dueDate, completedAt == nil else { return false }
        return hasDueTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    // MARK: Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, title, notes, steps, createdAt, completedAt
        case priorityRaw, dueDate, reminderOffsetRaw, sortOrder, listId, labelIds, recurrence
        case reminderId, lastSyncedAt, quadrant, matrixX, matrixY
        case isPinned, goalPeriod, hasDueTime
        case localModifiedAt, reminderCalendarId, reminderDueTimeZoneID
        case remoteRecurrenceRules, reminderRecurrenceWasEdited, spawnedRecurrenceID, recurrenceParentID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // Legacy payloads may omit `title` (early exports) or `notes`.
        // Fall back to safe defaults rather than failing to decode the whole
        // task — losing metadata is worse than losing a title we can't recover.
        // The title fallback is "Untitled" (not empty) so a decoded row is
        // always identifiable in the UI; an empty title otherwise renders as
        // an invisible row that the user can't select or edit.
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        steps = try c.decodeIfPresent([GoalStep].self, forKey: .steps) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        priorityRaw = try c.decodeIfPresent(Int.self, forKey: .priorityRaw) ?? Priority.medium.rawValue
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        reminderOffsetRaw = try c.decodeIfPresent(Int.self, forKey: .reminderOffsetRaw) ?? ReminderOffset.tenMinutes.rawValue
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        listId = try c.decodeIfPresent(UUID.self, forKey: .listId)
        labelIds = try c.decodeIfPresent([UUID].self, forKey: .labelIds) ?? []
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        reminderId = try c.decodeIfPresent(String.self, forKey: .reminderId)
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        quadrant = try c.decodeIfPresent(Quadrant.self, forKey: .quadrant)
        matrixX = try c.decodeIfPresent(Double.self, forKey: .matrixX)
        matrixY = try c.decodeIfPresent(Double.self, forKey: .matrixY)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        goalPeriod = try c.decodeIfPresent(GoalPeriod.self, forKey: .goalPeriod)
            ?? GoalPeriod.infer(due: dueDate, created: createdAt)
        hasDueTime = try c.decodeIfPresent(Bool.self, forKey: .hasDueTime) ?? false
        localModifiedAt = try c.decodeIfPresent(Date.self, forKey: .localModifiedAt)
        reminderCalendarId = try c.decodeIfPresent(String.self, forKey: .reminderCalendarId)
        reminderDueTimeZoneID = try c.decodeIfPresent(String.self, forKey: .reminderDueTimeZoneID)
        remoteRecurrenceRules = try c.decodeIfPresent([ReminderRecurrenceRule].self, forKey: .remoteRecurrenceRules)
        reminderRecurrenceWasEdited = try c.decodeIfPresent(Bool.self, forKey: .reminderRecurrenceWasEdited)
        spawnedRecurrenceID = try c.decodeIfPresent(UUID.self, forKey: .spawnedRecurrenceID)
        recurrenceParentID = try c.decodeIfPresent(UUID.self, forKey: .recurrenceParentID)
    }

    // MARK: Init

    init(
        title: String,
        notes: String = "",
        steps: [GoalStep] = [],
        priority: Priority = .medium,
        dueDate: Date? = nil,
        reminderOffset: ReminderOffset = .tenMinutes,
        listId: UUID? = nil,
        labelIds: [UUID] = [],
        recurrence: Recurrence? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.steps = GoalStep.normalized(steps)
        self.createdAt = Date()
        self.completedAt = nil
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.reminderOffsetRaw = reminderOffset.rawValue
        self.sortOrder = 0
        self.listId = listId
        self.labelIds = labelIds
        self.recurrence = recurrence
        self.reminderId = nil
        self.lastSyncedAt = nil
        self.quadrant = nil
        self.matrixX = nil
        self.matrixY = nil
        self.isPinned = false
        self.goalPeriod = GoalPeriod.infer(due: dueDate, created: self.createdAt)
        self.hasDueTime = false
        self.localModifiedAt = nil
        self.reminderCalendarId = nil
        self.reminderDueTimeZoneID = nil
        self.remoteRecurrenceRules = nil
        self.reminderRecurrenceWasEdited = nil
        self.spawnedRecurrenceID = nil
        self.recurrenceParentID = nil
    }
}
