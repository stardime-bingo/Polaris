// Store.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import Foundation
import SwiftUI
import os

/// Persistent task store backed by JSON files in Application Support.
@Observable
final class Store {
    static let shared = Store()

    /// Current on-disk data schema version. Bump when the persisted shape
    /// changes and add a corresponding migration step in `migrateIfNeeded()`.
    static let currentSchemaVersion = 2

    @ObservationIgnored private let logger = Logger(subsystem: "com.bingowu.polaris", category: "store")

    var items: [TodoItem] = []
    var lists: [TaskList] = []
    var labels: [TaskLabel] = []
    var activeListId: UUID
    var activeLabelFilter: UUID?

    @ObservationIgnored private let dir: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let performsSideEffects: Bool
    @ObservationIgnored var remindersSyncOverride: RemindersSync?
    var lastPersistenceError: String?
    private(set) var pendingReminderDeletions: [TodoItem] = []

    private var tasksURL: URL { dir.appendingPathComponent("tasks.json") }
    private var listsURL: URL { dir.appendingPathComponent("lists.json") }
    private var labelsURL: URL { dir.appendingPathComponent("labels.json") }

    /// Per-dataset write gates. Set to `false` only when we detect an
    /// unreadable on-disk file AND fail to back it up — in that case a
    /// subsequent save would overwrite the user's only remaining copy with
    /// an in-memory empty collection. Missing or clean files leave these
    /// flags `true` so normal operation is fully writable.
    private var tasksWritable = true
    private var listsWritable = true
    private var labelsWritable = true

    init(directory: URL? = nil, defaults: UserDefaults = .standard, performsSideEffects: Bool = true) {
        self.defaults = defaults
        self.performsSideEffects = performsSideEffects
        dir = directory ?? DocketRuntime.previewDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Polaris", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        activeListId = UUID()
        loadLists()
        loadLabels()
        loadTasks()
        let deletionURL = dir.appendingPathComponent("pending-reminder-deletions.json")
        if FileManager.default.fileExists(atPath: deletionURL.path) {
            do { pendingReminderDeletions = try JSONDecoder().decode([TodoItem].self, from: Data(contentsOf: deletionURL)) }
            catch { lastPersistenceError = "读取待同步删除失败：\(error.localizedDescription)" }
        }
        // Invariant: there is always at least one list, and exactly one default.
        if lists.isEmpty {
            lists = [TaskList(name: "Default", isDefault: true)]
            saveLists()
        }
        let defaultId = lists.first(where: { $0.isDefault })?.id ?? lists[0].id
        // Reassign any task pointing at a nil or non-existent list, and if that
        // actually changed something, persist so the healed state survives a
        // crash before the next mutation.
        if reassignOrphans() { saveTasks() }
        activeListId = UUID(uuidString: defaults.string(forKey: "activeListId") ?? "") ?? defaultId
        migrateIfNeeded()
    }

    // MARK: - Schema Migration

    /// Runs any pending data migrations and records the current schema version.
    /// v2 adds local goal steps and the explicit weekly period. Legacy tasks
    /// decode with an empty step list; existing month/year periods stay unchanged.
    private func migrateIfNeeded() {
        let stored = defaults.object(forKey: "dataSchemaVersion") as? Int ?? 0
        guard stored < Store.currentSchemaVersion else { return }
        // switch stored {
        // case 0: migrateV0toV1(); fallthrough
        // default: break
        // }
        defaults.set(Store.currentSchemaVersion, forKey: "dataSchemaVersion")
        logger.info("Migrated data schema \(stored) → \(Store.currentSchemaVersion)")
    }

    // MARK: - Computed Views

    var activeList: TaskList {
        lists.first(where: { $0.id == activeListId })
            ?? lists.first
            ?? TaskList(name: "Default", isDefault: true)
    }

    var activeTasks: [TodoItem] {
        var tasks = items.filter { !$0.isCompleted && $0.listId == activeListId }
        if let labelId = activeLabelFilter {
            tasks = tasks.filter { $0.labelIds.contains(labelId) }
        }
        // Deterministic order: primary by sortOrder, secondary by createdAt
        // (stable across launches even when two rows share a sortOrder — which
        // can happen after imports or interrupted reorders).
        return GoalBoardRules.ordered(tasks)
    }

    var completedTasks: [TodoItem] {
        items.filter { $0.isCompleted && $0.listId == activeListId }
            .sorted { a, b in
                let ac = a.completedAt ?? .distantPast
                let bc = b.completedAt ?? .distantPast
                if ac != bc { return ac > bc }
                return a.createdAt > b.createdAt
            }
    }

    /// Number of tasks due today or overdue.
    ///
    /// The boundary is *strictly* before tomorrow midnight — using `<`, not
    /// `<=`. Otherwise a task due exactly at tomorrow 00:00 would count as
    /// "due today" for a whole day, which contradicts every other date-group
    /// in the app.
    var badgeCount: Int {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        let allLists = defaults.bool(forKey: "badgeAllLists")
        return items.filter {
            !$0.isCompleted &&
            (allLists || $0.listId == activeListId) &&
            $0.dueDate != nil && $0.dueDate! < endOfToday
        }.count
    }

    /// Tasks grouped by due date category for "By Due Date" sort mode.
    var groupedByDueDate: [(title: String, color: String, tasks: [TodoItem])] {
        var active = items.filter { !$0.isCompleted && $0.listId == activeListId }
        if let labelId = activeLabelFilter {
            active = active.filter { $0.labelIds.contains(labelId) }
        }
        let calendar = Calendar.current
        let now = Date()
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!

        let overdue = active.filter { $0.dueDate != nil && $0.isOverdue(at: now) }.sorted { $0.dueDate! < $1.dueDate! }
        let today = active.filter { $0.dueDate != nil && !$0.isOverdue(at: now) && $0.dueDate! < endOfToday }.sorted { $0.dueDate! < $1.dueDate! }
        let upcoming = active.filter { $0.dueDate != nil && $0.dueDate! >= endOfToday }.sorted { $0.dueDate! < $1.dueDate! }
        let noDate = active.filter { $0.dueDate == nil }.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt < b.createdAt
        }

        var groups: [(title: String, color: String, tasks: [TodoItem])] = []
        if !overdue.isEmpty { groups.append((L10n.overdue, "red", overdue)) }
        if !today.isEmpty { groups.append((L10n.today, "orange", today)) }
        if !upcoming.isEmpty { groups.append((L10n.upcoming, "blue", upcoming)) }
        if !noDate.isEmpty { groups.append((L10n.noDate, "gray", noDate)) }
        return groups
    }

    /// Tasks grouped by priority (High / Medium / Low) for "By Priority" sort mode.
    var groupedByPriority: [(title: String, color: String, tasks: [TodoItem])] {
        var active = items.filter { !$0.isCompleted && $0.listId == activeListId }
        if let labelId = activeLabelFilter {
            active = active.filter { $0.labelIds.contains(labelId) }
        }
        func bucket(_ p: Priority) -> [TodoItem] {
            active.filter { $0.priority == p }.sorted { a, b in
                if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                return a.createdAt < b.createdAt
            }
        }
        var groups: [(title: String, color: String, tasks: [TodoItem])] = []
        let high = bucket(.high), medium = bucket(.medium), low = bucket(.low)
        if !high.isEmpty { groups.append((L10n.priorityHigh, "red", high)) }
        if !medium.isEmpty { groups.append((L10n.priorityMedium, "orange", medium)) }
        if !low.isEmpty { groups.append((L10n.priorityLow, "blue", low)) }
        return groups
    }

    // MARK: - List Management

    func switchList(_ list: TaskList) {
        activeListId = list.id
        activeLabelFilter = nil
        defaults.set(list.id.uuidString, forKey: "activeListId")
    }

    // MARK: - Labels

    var labelsForActiveList: [TaskLabel] {
        labels.filter { $0.listId == activeListId }
    }

    func addLabel(name: String, colorHex: String, icon: String) {
        let label = TaskLabel(name: name, colorHex: colorHex, icon: icon, listId: activeListId)
        let before = labels
        labels.append(label)
        if !saveLabels() { labels = before }
    }

    func updateLabel(_ label: TaskLabel) {
        guard let i = labels.firstIndex(where: { $0.id == label.id }) else { return }
        let before = labels
        labels[i] = label
        if !saveLabels() { labels = before }
    }

    func deleteLabel(_ label: TaskLabel) {
        let oldItems = items, oldLabels = labels
        // Remove from all tasks
        for i in items.indices {
            items[i].labelIds.removeAll { $0 == label.id }
        }
        labels.removeAll { $0.id == label.id }
        guard persistAll() else { items = oldItems; labels = oldLabels; return }
        if activeLabelFilter == label.id { activeLabelFilter = nil }
    }

    func addList(name: String) {
        let list = TaskList(name: name)
        let before = lists
        lists.append(list)
        if !saveLists() { lists = before }
    }

    func renameList(_ list: TaskList, to name: String) {
        guard let i = lists.firstIndex(where: { $0.id == list.id }) else { return }
        let before = lists
        lists[i].name = name
        if !saveLists() { lists = before }
    }

    func deleteList(_ list: TaskList) {
        guard !list.isDefault, let defaultId = lists.first(where: { $0.isDefault })?.id else { return }
        let oldItems = items, oldLists = lists, oldLabels = labels
        let movedIDs = Set(items.filter { $0.listId == list.id }.map(\.id))
        var nextOrder = maxSortOrder(inListId: defaultId) + 1
        let allowedLabels = Set(labels.filter { $0.listId == defaultId }.map(\.id))
        for i in items.indices where movedIDs.contains(items[i].id) {
            items[i].listId = defaultId
            // Removing a list revokes its calendar permission. Detach safely;
            // do not issue an asynchronous delete against a revoked binding.
            items[i].reminderId = nil
            items[i].reminderCalendarId = nil
            items[i].lastSyncedAt = nil
            items[i].localModifiedAt = Date()
            items[i].labelIds.removeAll { !allowedLabels.contains($0) }
            if !items[i].isCompleted { items[i].sortOrder = nextOrder; nextOrder += 1 }
        }
        lists.removeAll { $0.id == list.id }
        labels.removeAll { $0.listId == list.id }
        guard persistAll() else { items = oldItems; lists = oldLists; labels = oldLabels; return }
        if activeListId == list.id, let fallback = lists.first(where: { $0.id == defaultId }) { switchList(fallback) }
        if let filter = activeLabelFilter, !labels.contains(where: { $0.id == filter }) { activeLabelFilter = nil }
        for item in items where movedIDs.contains(item.id) { syncPush(item) }
    }

    var menuBarGoal: TodoItem? {
        GoalBoardRules.featured(in: items, preferredID: defaults.string(forKey: "menuBarGoalID"))
    }

    func togglePin(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let before = items
        let wasPrimary = menuBarGoal?.id == item.id
        items[i].isPinned.toggle()
        guard saveTasks() else { items = before; return }
        if wasPrimary && !items[i].isPinned { defaults.set("none", forKey: "menuBarGoalID") }
    }

    func featureInMenuBar(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let before = items
        items[i].isPinned = true
        guard saveTasks() else { items = before; return }
        defaults.set(item.id.uuidString, forKey: "menuBarGoalID")
        defaults.set(true, forKey: "showGoalInMenuBar")
    }

    // MARK: - CRUD

    /// Highest sortOrder currently used inside a specific list (uncompleted
    /// tasks only). Independent of `activeListId` and `activeLabelFilter` so
    /// insertions can't collide just because the user happens to be viewing
    /// a filtered subset when the task is added.
    private func maxSortOrder(inListId listId: UUID?) -> Int {
        items.reduce(-1) { current, item in
            guard !item.isCompleted, item.listId == listId else { return current }
            return max(current, item.sortOrder)
        }
    }

    @discardableResult
    func add(_ item: TodoItem) -> Bool {
        guard !items.contains(where: { $0.id == item.id }) else { return false }
        let before = items
        var newItem = item
        newItem.steps = GoalStep.normalized(newItem.steps)
        if newItem.listId == nil { newItem.listId = activeListId }
        guard lists.contains(where: { $0.id == newItem.listId }) else { return false }
        let allowed = Set(labels.filter { $0.listId == newItem.listId }.map(\.id))
        newItem.labelIds.removeAll { !allowed.contains($0) }
        newItem.sortOrder = maxSortOrder(inListId: newItem.listId) + 1
        newItem.localModifiedAt = Date()
        items.append(newItem)
        guard saveTasks() else { items = before; return false }
        scheduleReminder(newItem)
        syncPush(newItem)
        return true
    }

    @discardableResult
    func importData(lists newLists: [TaskList], labels newLabels: [TaskLabel], tasks newTasks: [TodoItem]) -> Bool {
        let oldItems = items, oldLists = lists, oldLabels = labels
        guard Set(lists.map(\.id)).isDisjoint(with: newLists.map(\.id)),
              Set(labels.map(\.id)).isDisjoint(with: newLabels.map(\.id)),
              Set(items.map(\.id)).isDisjoint(with: newTasks.map(\.id)),
              Set(newLists.map(\.id)).count == newLists.count,
              Set(newLabels.map(\.id)).count == newLabels.count,
              Set(newTasks.map(\.id)).count == newTasks.count else {
            lastPersistenceError = "导入标识冲突，未写入数据。"; return false
        }
        lists.append(contentsOf: newLists)
        labels.append(contentsOf: newLabels)
        for var task in newTasks {
            if task.listId == nil { task.listId = activeListId }
            guard lists.contains(where: { $0.id == task.listId }) else {
                items = oldItems; lists = oldLists; labels = oldLabels
                lastPersistenceError = "导入目标引用了不存在的目标集。"; return false
            }
            let allowed = Set(labels.filter { $0.listId == task.listId }.map(\.id))
            task.labelIds.removeAll { !allowed.contains($0) }
            task.sortOrder = maxSortOrder(inListId: task.listId) + 1
            task.localModifiedAt = Date()
            items.append(task)
        }
        guard persistAll() else { items = oldItems; lists = oldLists; labels = oldLabels; return false }
        let inserted = Set(newTasks.map(\.id))
        for task in items where inserted.contains(task.id) { scheduleReminder(task); syncPush(task) }
        return true
    }

    @discardableResult
    func complete(_ item: TodoItem) -> Bool {
        finish(item, at: Date(), fromRemote: false)
    }

    @discardableResult
    func completeFromRemote(_ item: TodoItem, at date: Date) -> Bool {
        finish(item, at: date, fromRemote: true)
    }

    private func finish(_ item: TodoItem, at date: Date, fromRemote: Bool) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return false }
        guard !items[i].isCompleted else { return true }
        let before = items
        items[i].completedAt = date
        if !fromRemote { items[i].localModifiedAt = Date() }
        let next = spawnRecurrenceIfNeeded(after: items[i])
        guard saveTasks() else { items = before; return false }
        cancelReminder(items[i])
        if let next { scheduleReminder(next); syncPush(next) }
        if !fromRemote { syncPush(items[i]) }
        return true
    }

    /// Mutates memory only. The caller commits the completion and successor
    /// together before either notifications or remote writes are allowed.
    @discardableResult
    func spawnRecurrenceIfNeeded(after completed: TodoItem) -> TodoItem? {
        guard completed.spawnedRecurrenceID == nil, !completed.hasRemoteRecurrence,
              let parent = items.firstIndex(where: { $0.id == completed.id }),
              let recurrence = completed.recurrence, let due = completed.dueDate,
              let nextDate = recurrence.nextDueDate(from: due) else { return nil }
        var next = completed
        next.id = UUID()
        next.createdAt = Date()
        next.localModifiedAt = next.createdAt
        next.completedAt = nil
        next.steps = completed.steps.map { $0.forNextOccurrence() }
        next.dueDate = nextDate
        next.reminderId = nil
        next.reminderCalendarId = nil
        next.isPinned = false
        next.lastSyncedAt = nil
        next.spawnedRecurrenceID = nil
        next.recurrenceParentID = completed.id
        next.sortOrder = maxSortOrder(inListId: next.listId) + 1
        items[parent].spawnedRecurrenceID = next.id
        items.append(next)
        return next
    }

    /// Immediate undo retracts only the untouched successor created by this
    /// completion. An edited/completed successor belongs to the user already.
    @discardableResult
    func undoCompletion(_ item: TodoItem) -> Bool {
        guard let parent = items.first(where: { $0.id == item.id }), parent.isCompleted else { return false }
        let before = items
        let child = items.first { $0.id == parent.spawnedRecurrenceID && $0.recurrenceParentID == parent.id && !$0.isCompleted && ($0.localModifiedAt ?? $0.createdAt) <= $0.createdAt }
        if let child {
            guard prepareReminderDeletions([child]) else { return false }
            items.removeAll { $0.id == child.id }
        }
        guard let i = items.firstIndex(where: { $0.id == parent.id }) else { return false }
        items[i].completedAt = nil
        items[i].localModifiedAt = Date()
        if child != nil { items[i].spawnedRecurrenceID = nil }
        guard saveTasks() else { items = before; return false }
        if let child { cancelReminder(child); syncDelete(child) }
        scheduleReminder(items[i])
        syncPush(items[i])
        return true
    }

    /// Archive restore retains the successor association, so completing the
    /// restored historical occurrence cannot spawn the same period again.
    @discardableResult
    func restore(_ item: TodoItem) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return false }
        guard items[i].isCompleted else { return true }
        let before = items
        items[i].completedAt = nil
        items[i].localModifiedAt = Date()
        items[i].sortOrder = maxSortOrder(inListId: items[i].listId) + 1
        guard saveTasks() else { items = before; return false }
        scheduleReminder(items[i]); syncPush(items[i])
        return true
    }

    /// Steps are local to Polaris. Toggle the latest value without replaying a
    /// stale row snapshot, rescheduling the goal, or pushing Apple-owned fields.
    @discardableResult
    func toggleStep(goalID: UUID, stepID: UUID) -> Bool {
        guard let goal = items.firstIndex(where: { $0.id == goalID && !$0.isCompleted }),
              let step = items[goal].steps.firstIndex(where: { $0.id == stepID }) else { return false }
        let before = items
        items[goal].steps[step].isCompleted.toggle()
        guard saveTasks() else { items = before; return false }
        return true
    }

    @discardableResult
    func update(_ item: TodoItem) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == item.id }), lists.contains(where: { $0.id == item.listId }) else { return false }
        let before = items, previous = items[i]
        var updated = item
        updated.steps = GoalStep.normalized(updated.steps)
        // An editor may have opened before a sync callback assigned identity.
        updated.reminderId = previous.reminderId
        updated.reminderCalendarId = previous.reminderCalendarId
        updated.lastSyncedAt = previous.lastSyncedAt
        updated.spawnedRecurrenceID = previous.spawnedRecurrenceID
        updated.recurrenceParentID = previous.recurrenceParentID
        updated.localModifiedAt = Date()
        if previous.recurrence != updated.recurrence || (item.reminderRecurrenceWasEdited == true && item.remoteRecurrenceRules == nil) {
            updated.remoteRecurrenceRules = nil
            updated.reminderRecurrenceWasEdited = true
        } else {
            updated.remoteRecurrenceRules = previous.remoteRecurrenceRules
            updated.reminderRecurrenceWasEdited = previous.reminderRecurrenceWasEdited
        }
        let allowed = Set(labels.filter { $0.listId == updated.listId }.map(\.id))
        updated.labelIds.removeAll { !allowed.contains($0) }
        if previous.listId != updated.listId {
            let source = previous.reminderCalendarId ?? lists.first(where: { $0.id == previous.listId })?.remindersCalendarId
            let destination = lists.first(where: { $0.id == updated.listId })?.remindersCalendarId
            if let source, destination != nil, lists.contains(where: { $0.remindersCalendarId == source }) {
                updated.reminderCalendarId = source // pending migration, protected from destination pull deletion
            } else {
                updated.reminderId = nil
                updated.reminderCalendarId = nil
                updated.lastSyncedAt = nil
            }
            updated.sortOrder = maxSortOrder(inListId: updated.listId) + 1
        }
        items[i] = updated
        guard saveTasks() else { items = before; return false }
        scheduleReminder(updated); syncPush(updated)
        return true
    }

    @discardableResult
    func delete(_ item: TodoItem) -> Bool {
        guard let current = items.first(where: { $0.id == item.id }) else { return false }
        guard prepareReminderDeletions([current]) else { return false }
        let before = items
        items.removeAll { $0.id == current.id }
        guard saveTasks() else { items = before; return false }
        cancelReminder(current); syncDelete(current)
        return true
    }

    @discardableResult
    func deleteFromRemote(_ item: TodoItem) -> Bool {
        let before = items
        items.removeAll { $0.id == item.id }
        guard saveTasks() else { items = before; return false }
        cancelReminder(item)
        return true
    }

    // MARK: - Reorder

    func move(from source: IndexSet, to destination: Int) {
        let before = items
        var active = activeTasks
        active.move(fromOffsets: source, toOffset: destination)
        for (idx, task) in active.enumerated() {
            if let i = items.firstIndex(where: { $0.id == task.id }) {
                items[i].sortOrder = idx
            }
        }
        if !saveTasks() { items = before }
    }

    /// Persist an explicit order for the given task ids (the visible custom-sorted
    /// set). Each id's `sortOrder` becomes its position in the array. Used by the
    /// drag-to-reorder gesture.
    func applyManualOrder(_ orderedIds: [UUID]) {
        let before = items
        for (idx, id) in orderedIds.enumerated() {
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].sortOrder = idx
            }
        }
        if !saveTasks() { items = before }
    }

    @discardableResult
    func clearCompleted() -> Bool {
        let before = items
        let doomed = items.filter { $0.isCompleted && $0.listId == activeListId }
        guard prepareReminderDeletions(doomed) else { return false }
        let ids = Set(doomed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        guard saveTasks() else { items = before; return false }
        for item in doomed { cancelReminder(item); syncDelete(item) }
        return true
    }

    // MARK: - Persistence

    /// Copy an unreadable JSON file to a timestamped `.corrupt` backup so a
    /// subsequent successful save doesn't silently overwrite the user's only
    /// remaining copy of their data. Returns `true` when a backup is safely
    /// on disk (or the source didn't exist to begin with) — in which case
    /// the caller may keep the dataset writable, since a fresh save will
    /// overwrite the still-in-place corrupt original but the copy preserves
    /// the data. Returns `false` when the copy failed: the caller MUST
    /// disable writes for this dataset for the rest of the process,
    /// otherwise a permission or disk problem would take the user's data
    /// with it on the next mutation.
    ///
    /// We prefer `copyItem` over `moveItem` so the original path stays
    /// occupied by the (corrupt) file. If we cannot make a backup, blocking
    /// writes on top of the still-present original preserves the file
    /// bit-for-bit for hand-recovery.
    @discardableResult
    private func quarantineCorruptFile(at url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return true }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-") // ':' is a legal filename char but ugly
        let dest = url.appendingPathExtension("corrupt-\(stamp)")
        do {
            try fm.copyItem(at: url, to: dest)
            logger.error("Backed up corrupt file \(url.lastPathComponent) → \(dest.lastPathComponent)")
            return true
        } catch {
            logger.error("Could not back up corrupt file at \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    private func loadTasks() {
        guard FileManager.default.fileExists(atPath: tasksURL.path) else { return }
        do {
            let data = try Data(contentsOf: tasksURL)
            items = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch {
            logger.error("Failed to load tasks: \(error.localizedDescription)")
            // Preserve the corrupt file so the user (or a rescue script) can
            // hand-recover from it — we would otherwise happily overwrite it
            // with an empty array on the next mutation. If we can't back it
            // up, block writes for the rest of the process so the original
            // stays intact on disk.
            if !quarantineCorruptFile(at: tasksURL) {
                tasksWritable = false
                logger.error("tasks.json backup failed — disabling task writes for this session to preserve the on-disk file")
            }
        }
    }

    @discardableResult
    private func saveTasks() -> Bool {
        save(items, to: tasksURL, writable: tasksWritable, notify: true)
    }

    private func save<T: Encodable>(_ value: T, to url: URL, writable: Bool = true, notify: Bool = false) -> Bool {
        guard writable else { lastPersistenceError = "无法保存 \(url.lastPathComponent)：原文件恢复失败，写入已暂停。"; return false }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            lastPersistenceError = nil
            if notify && performsSideEffects { NotificationCenter.default.post(name: .goalBoardChanged, object: nil) }
            return true
        } catch {
            lastPersistenceError = "保存 \(url.lastPathComponent) 失败：\(error.localizedDescription)"
            logger.error("\(self.lastPersistenceError ?? "")")
            return false
        }
    }

    private func loadLists() {
        guard FileManager.default.fileExists(atPath: listsURL.path) else {
            lists = [TaskList(name: "Default", isDefault: true)]
            saveLists()
            return
        }
        do {
            let data = try Data(contentsOf: listsURL)
            let decoded = try JSONDecoder().decode([TaskList].self, from: data)
            if !decoded.isEmpty { lists = decoded }
        } catch {
            logger.error("Failed to load lists: \(error.localizedDescription)")
            if !quarantineCorruptFile(at: listsURL) {
                listsWritable = false
                logger.error("lists.json backup failed — disabling list writes for this session to preserve the on-disk file")
            }
            // Init() will recreate a default list if this left `lists` empty.
            // The default is kept in-memory only when writes are disabled.
        }
    }

    @discardableResult
    private func saveLists() -> Bool { save(lists, to: listsURL, writable: listsWritable) }

    @discardableResult
    func persist() -> Bool { persistAll() }

    /// Multi-file saves retain the previous bytes and roll back earlier writes
    /// on a later failure. Errors remain observable, including rollback errors.
    @discardableResult
    func persistAll() -> Bool {
        guard tasksWritable && listsWritable && labelsWritable else {
            lastPersistenceError = "原文件恢复失败，保存已暂停。"; return false
        }
        var originals: [(URL, Data?)] = []
        var written: [URL] = []
        do {
            let encoded = [(tasksURL, try JSONEncoder().encode(items)), (listsURL, try JSONEncoder().encode(lists)), (labelsURL, try JSONEncoder().encode(labels))]
            for (url, _) in encoded {
                originals.append((url, FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil))
            }
            for (url, data) in encoded { try data.write(to: url, options: .atomic); written.append(url) }
            lastPersistenceError = nil
            if performsSideEffects { NotificationCenter.default.post(name: .goalBoardChanged, object: nil) }
            return true
        } catch {
            var message = "保存失败：\(error.localizedDescription)"
            for (url, bytes) in originals.reversed() where written.contains(url) {
                do {
                    if let bytes { try bytes.write(to: url, options: .atomic) }
                    else { try FileManager.default.removeItem(at: url) }
                } catch { message += "；恢复 \(url.lastPathComponent) 失败：\(error.localizedDescription)" }
            }
            lastPersistenceError = message
            logger.error("\(message)")
            return false
        }
    }

    @discardableResult
    func recordReminderDeletion(_ item: TodoItem) -> Bool {
        guard item.reminderId != nil else { return true }
        let before = pendingReminderDeletions
        pendingReminderDeletions.removeAll { $0.reminderId == item.reminderId }
        pendingReminderDeletions.append(item)
        guard save(pendingReminderDeletions, to: dir.appendingPathComponent("pending-reminder-deletions.json")) else {
            pendingReminderDeletions = before; return false
        }
        return true
    }

    @discardableResult
    func acknowledgeReminderDeletion(_ reminderId: String) -> Bool {
        let before = pendingReminderDeletions
        pendingReminderDeletions.removeAll { $0.reminderId == reminderId }
        guard save(pendingReminderDeletions, to: dir.appendingPathComponent("pending-reminder-deletions.json")) else {
            pendingReminderDeletions = before; return false
        }
        return true
    }

    /// Re-run the orphan-assignment pass: any task whose listId is nil or
    /// points to a list that no longer exists is moved to the default list.
    /// Mirrors the logic in `init()` but is safe to call at runtime (e.g.
    /// after an import). Returns true if any task was changed.
    @discardableResult
    func reassignOrphans() -> Bool {
        let validIds = Set(lists.map(\.id))
        let defaultId = lists.first(where: { $0.isDefault })?.id ?? lists[0].id
        var changed = false
        for i in items.indices where items[i].listId == nil || !validIds.contains(items[i].listId!) {
            items[i].listId = defaultId
            changed = true
        }
        return changed
    }

    /// Atomically mutate a single item by id and persist. Centralises the
    /// "find index → mutate → persist" pattern used by drag-driven views.
    /// No-op if the id isn't found.
    @discardableResult
    func mutate(_ id: UUID, _ mutator: (inout TodoItem) -> Void) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        var changed = items[i]
        mutator(&changed)
        return update(changed)
    }

    private func loadLabels() {
        guard FileManager.default.fileExists(atPath: labelsURL.path) else { return }
        do {
            let data = try Data(contentsOf: labelsURL)
            labels = try JSONDecoder().decode([TaskLabel].self, from: data)
        } catch {
            logger.error("Failed to load labels: \(error.localizedDescription)")
            if !quarantineCorruptFile(at: labelsURL) {
                labelsWritable = false
                logger.error("labels.json backup failed — disabling label writes for this session to preserve the on-disk file")
            }
        }
    }

    @discardableResult
    private func saveLabels() -> Bool { save(labels, to: labelsURL, writable: labelsWritable) }

    // MARK: - Side effects (isolated tests never touch notifications/accounts)

    func scheduleReminder(_ item: TodoItem) {
        if performsSideEffects && !DocketRuntime.isPreview { NotificationManager.shared.scheduleReminder(for: item) }
    }

    func cancelReminder(_ item: TodoItem) {
        if performsSideEffects && !DocketRuntime.isPreview { NotificationManager.shared.cancelReminder(for: item) }
    }

    private var syncService: RemindersSync? {
        if let override = remindersSyncOverride { return override }
        return performsSideEffects && !DocketRuntime.isPreview ? RemindersSync.shared : nil
    }

    private func prepareReminderDeletions(_ items: [TodoItem]) -> Bool {
        guard let service = syncService else { return true }
        for item in items {
            if let snapshot = service.deletionSnapshot(for: item), !recordReminderDeletion(snapshot) { return false }
        }
        return true
    }

    private func syncDelete(_ item: TodoItem) { syncService?.deleteReminder(for: item) }

    private func syncPush(_ item: TodoItem) {
        guard defaults.bool(forKey: "remindersSyncEnabled") else { return }
        let list = lists.first(where: { $0.id == item.listId })
        syncService?.pushTask(item, calendarId: list?.remindersCalendarId)
    }
}
