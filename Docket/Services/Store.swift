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
    static let currentSchemaVersion = 1

    @ObservationIgnored private let logger = Logger(subsystem: "blog.insecurity.docket", category: "store")

    var items: [TodoItem] = []
    var lists: [TaskList] = []
    var labels: [TaskLabel] = []
    var activeListId: UUID
    var activeLabelFilter: UUID?

    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Docket", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

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

    init() {
        activeListId = UUID()
        loadLists()
        loadLabels()
        loadTasks()
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
        activeListId = UUID(uuidString: UserDefaults.standard.string(forKey: "activeListId") ?? "") ?? defaultId
        migrateIfNeeded()
    }

    // MARK: - Schema Migration

    /// Runs any pending data migrations and records the current schema version.
    /// Currently a no-op scaffold (we're at v1); future schema changes add
    /// sequential migration steps here.
    private func migrateIfNeeded() {
        let stored = UserDefaults.standard.object(forKey: "dataSchemaVersion") as? Int ?? 0
        guard stored < Store.currentSchemaVersion else { return }
        // switch stored {
        // case 0: migrateV0toV1(); fallthrough
        // default: break
        // }
        UserDefaults.standard.set(Store.currentSchemaVersion, forKey: "dataSchemaVersion")
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
        return tasks.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt < b.createdAt
        }
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
        let allLists = UserDefaults.standard.bool(forKey: "badgeAllLists")
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

        let overdue = active.filter { $0.dueDate != nil && $0.dueDate! < now }.sorted { $0.dueDate! < $1.dueDate! }
        let today = active.filter { $0.dueDate != nil && $0.dueDate! >= now && $0.dueDate! < endOfToday }.sorted { $0.dueDate! < $1.dueDate! }
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
        UserDefaults.standard.set(list.id.uuidString, forKey: "activeListId")
    }

    // MARK: - Labels

    var labelsForActiveList: [TaskLabel] {
        labels.filter { $0.listId == activeListId }
    }

    func addLabel(name: String, colorHex: String, icon: String) {
        let label = TaskLabel(name: name, colorHex: colorHex, icon: icon, listId: activeListId)
        labels.append(label)
        saveLabels()
    }

    func updateLabel(_ label: TaskLabel) {
        guard let i = labels.firstIndex(where: { $0.id == label.id }) else { return }
        labels[i] = label
        saveLabels()
    }

    func deleteLabel(_ label: TaskLabel) {
        // Remove from all tasks
        for i in items.indices {
            items[i].labelIds.removeAll { $0 == label.id }
        }
        labels.removeAll { $0.id == label.id }
        if activeLabelFilter == label.id { activeLabelFilter = nil }
        saveLabels()
        saveTasks()
    }

    func addList(name: String) {
        let list = TaskList(name: name)
        lists.append(list)
        saveLists()
    }

    func renameList(_ list: TaskList, to name: String) {
        guard let i = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[i].name = name
        saveLists()
    }

    func deleteList(_ list: TaskList) {
        guard !list.isDefault else { return }
        guard let defaultId = lists.first(where: { $0.isDefault })?.id else { return }
        // Collect the ids of labels owned by the list being deleted. Labels
        // are per-list, so these become orphans the moment the list goes
        // away — they'd remain in labels.json referenced by moved tasks but
        // hidden from every label picker (which filters by activeListId).
        let doomedLabelIds = Set(labels.filter { $0.listId == list.id }.map(\.id))

        // Snapshot the tasks in the doomed list BEFORE any mutation. Two
        // reasons: (1) each snapshot still carries the pre-move reminderId,
        // which is what EventKit needs to delete the reminder in the *old*
        // calendar; (2) freezing membership up front means the mutation
        // loop below only touches existing rows (no append/remove), so
        // `items.indices` stays stable for its whole traversal.
        let doomedTaskSnapshots = items.filter { $0.listId == list.id }
        let doomedIds = Set(doomedTaskSnapshots.map(\.id))

        // Enqueue deletion of the corresponding EventKit reminders using
        // the snapshotted reminderIds. RemindersSync copies `rid` out of
        // the item before hopping to its serial queue, so it's safe to
        // then wipe the local reminderId in the mutation loop below — the
        // async delete still sees the correct old identifier. If we
        // instead let the moved task retain the doomed reminderId, a
        // later pull of the default list's calendar would see that id
        // absent and delete the moved local task (the very bug we're
        // fixing).
        for snap in doomedTaskSnapshots where snap.reminderId != nil {
            RemindersSync.shared.deleteReminder(for: snap)
        }

        // Compute a collision-free block of sortOrders at the tail of the
        // default list and assign it deterministically to the moved
        // *active* tasks. We deliberately use `maxSortOrder(inListId:)`
        // (not `activeTasks`) so the result is independent of whichever
        // list/label filter the user happens to be viewing. Completed
        // tasks aren't reordered — they're grouped by completedAt in the
        // UI, and their sortOrder is irrelevant there.
        let baseSortOrder = maxSortOrder(inListId: defaultId) + 1
        let movedActiveOrdered = doomedTaskSnapshots
            .filter { !$0.isCompleted }
            .sorted { a, b in
                if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                return a.createdAt < b.createdAt
            }
        var newSortOrderById: [UUID: Int] = [:]
        for (offset, snap) in movedActiveOrdered.enumerated() {
            newSortOrderById[snap.id] = baseSortOrder + offset
        }

        // Move tasks to default, clearing sync state that only made sense
        // in the old calendar and stripping any label references that
        // pointed at labels owned by the deleted list. Labels belonging
        // to other lists are preserved — they'd be filtered out at render
        // time anyway (labels are scoped by list), but keeping the ids
        // around means restoring a task to its original list via undo
        // would bring the correct labels back if we ever add such a
        // feature.
        for i in items.indices where doomedIds.contains(items[i].id) {
            items[i].listId = defaultId
            // Reminder in the doomed calendar is being deleted above; the
            // moved task must not retain a link into that calendar or a
            // subsequent pull of the default list would see the id
            // missing and remotely-delete the moved local task.
            items[i].reminderId = nil
            items[i].lastSyncedAt = nil
            if !doomedLabelIds.isEmpty {
                items[i].labelIds.removeAll { doomedLabelIds.contains($0) }
            }
            if let newOrder = newSortOrderById[items[i].id] {
                items[i].sortOrder = newOrder
            }
        }

        // Drop the doomed labels themselves and clear any active filter
        // that would suddenly reference a nonexistent label.
        if !doomedLabelIds.isEmpty {
            labels.removeAll { doomedLabelIds.contains($0.id) }
            if let filter = activeLabelFilter, doomedLabelIds.contains(filter) {
                activeLabelFilter = nil
            }
        }

        lists.removeAll { $0.id == list.id }
        if activeListId == list.id,
           let fallback = lists.first(where: { $0.isDefault }) ?? lists.first {
            switchList(fallback)
        }
        saveLists()
        saveLabels()
        saveTasks()

        // With local state persisted and reminderId cleared, push each
        // moved task through the normal sync path. `syncPush` resolves
        // the destination calendar from the (now-updated) task.listId, so
        // this creates fresh reminders in the default list's calendar
        // (or is a no-op when the default list isn't a synced list, or
        // when Reminders sync is off). The push completion writes the
        // freshly-minted reminderId + lastSyncedAt back to the store and
        // re-persists.
        for id in doomedIds {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                syncPush(items[idx])
            }
        }
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

    func add(_ item: TodoItem) {
        var newItem = item
        // Preserve the caller's chosen list if they set one; otherwise land in
        // the currently active list. This matters for spawns from
        // Reminders-imported tasks (whose `listId` was set by the merge code)
        // and for programmatic imports.
        if newItem.listId == nil {
            newItem.listId = activeListId
        }
        newItem.sortOrder = maxSortOrder(inListId: newItem.listId) + 1
        items.append(newItem)
        saveTasks()
        NotificationManager.shared.scheduleReminder(for: newItem)
        syncPush(newItem)
    }

    func complete(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].completedAt = Date()
        NotificationManager.shared.cancelReminder(for: items[i])

        spawnRecurrenceIfNeeded(after: items[i])

        syncPush(items[i])
        saveTasks()
    }

    /// Mark an item complete as a *result* of a remote (Reminders) change.
    /// Same local bookkeeping as `complete(_:)` but without pushing the
    /// completion back to Reminders — that would be a redundant round trip
    /// and, if a merge conflict has already been resolved, could clobber a
    /// newer state.
    func completeFromRemote(_ item: TodoItem, at date: Date) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        // Nothing to do if we already recorded this completion.
        if items[i].completedAt != nil { return }
        items[i].completedAt = date
        NotificationManager.shared.cancelReminder(for: items[i])
        spawnRecurrenceIfNeeded(after: items[i])
        saveTasks()
    }

    /// Spawn the next occurrence of a recurring task once the given item has
    /// just been marked complete. Extracted so the local and remote
    /// completion paths behave identically.
    private func spawnRecurrenceIfNeeded(after completed: TodoItem) {
        guard let recurrence = completed.recurrence,
              let dueDate = completed.dueDate,
              let nextDate = recurrence.nextDueDate(from: dueDate) else { return }
        var next = completed
        next.id = UUID()
        next.createdAt = Date()
        next.completedAt = nil
        next.dueDate = nextDate
        next.reminderId = nil
        // Fresh occurrence: no sync stamp yet — otherwise a subsequent pull
        // could think this brand-new local task is "older than remote" and
        // overwrite fields the user hasn't seen yet.
        next.lastSyncedAt = nil
        // Order the new instance at the end of *its own* list, computed
        // independently of the active label filter (a filtered activeTasks
        // could be empty and produce sortOrder = 0, colliding with existing
        // items).
        next.sortOrder = maxSortOrder(inListId: next.listId) + 1
        items.append(next)
        NotificationManager.shared.scheduleReminder(for: next)
        syncPush(next)
    }

    func restore(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].completedAt = nil
        // Restore into the item's own list, not the active list, so a restore
        // from a filtered view doesn't silently move the task.
        items[i].sortOrder = maxSortOrder(inListId: items[i].listId) + 1
        saveTasks()
        NotificationManager.shared.scheduleReminder(for: items[i])
        syncPush(items[i])
    }

    func update(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = items[i]
        var updated = item

        // If the item moved lists, clean up state that only made sense in the
        // old list.
        if previous.listId != updated.listId {
            // Labels are per-list — strip any that aren't owned by the
            // destination list, or they'd render as orphaned pills.
            let destLabels = Set(labels.filter { $0.listId == updated.listId }.map(\.id))
            updated.labelIds = updated.labelIds.filter { destLabels.contains($0) }
            // Recompute a collision-free sortOrder at the end of the
            // destination list, disregarding filters entirely.
            updated.sortOrder = maxSortOrder(inListId: updated.listId) + 1
        }

        items[i] = updated
        saveTasks()
        NotificationManager.shared.scheduleReminder(for: updated)
        syncPush(updated)
    }

    func delete(_ item: TodoItem) {
        RemindersSync.shared.deleteReminder(for: item)
        items.removeAll { $0.id == item.id }
        saveTasks()
        NotificationManager.shared.cancelReminder(for: item)
    }

    /// Delete a task as a *result* of a remote (Reminders) change — skips the
    /// EventKit round trip since the reminder is already gone.
    func deleteFromRemote(_ item: TodoItem) {
        NotificationManager.shared.cancelReminder(for: item)
        items.removeAll { $0.id == item.id }
        saveTasks()
    }

    // MARK: - Reorder

    func move(from source: IndexSet, to destination: Int) {
        var active = activeTasks
        active.move(fromOffsets: source, toOffset: destination)
        for (idx, task) in active.enumerated() {
            if let i = items.firstIndex(where: { $0.id == task.id }) {
                items[i].sortOrder = idx
            }
        }
        saveTasks()
    }

    /// Persist an explicit order for the given task ids (the visible custom-sorted
    /// set). Each id's `sortOrder` becomes its position in the array. Used by the
    /// drag-to-reorder gesture.
    func applyManualOrder(_ orderedIds: [UUID]) {
        for (idx, id) in orderedIds.enumerated() {
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].sortOrder = idx
            }
        }
        saveTasks()
    }

    func clearCompleted() {
        // Snapshot the doomed tasks BEFORE mutating `items` so we (a) don't
        // mutate the collection while iterating over it, and (b) still have
        // the reminderId / notification identifier of each task at hand.
        //
        // Without this cleanup, a later Reminders pull would see the remote
        // reminders that we forgot to delete and happily re-import them as
        // brand-new local tasks (since the local `reminderId` is gone with
        // the row). Local notifications would similarly linger and fire for
        // tasks the user has explicitly cleared.
        let doomed = items.filter { $0.isCompleted && $0.listId == activeListId }
        for item in doomed {
            NotificationManager.shared.cancelReminder(for: item)
            RemindersSync.shared.deleteReminder(for: item)
        }
        let doomedIds = Set(doomed.map(\.id))
        items.removeAll { doomedIds.contains($0.id) }
        saveTasks()
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

    private func saveTasks() {
        guard tasksWritable else {
            logger.warning("Skipping tasks save — writes are disabled after a failed corrupt-file backup")
            return
        }
        do {
            try JSONEncoder().encode(items).write(to: tasksURL, options: .atomic)
        } catch {
            logger.error("Failed to save tasks: \(error.localizedDescription)")
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

    private func saveLists() {
        guard listsWritable else {
            logger.warning("Skipping lists save — writes are disabled after a failed corrupt-file backup")
            return
        }
        do {
            try JSONEncoder().encode(lists).write(to: listsURL, options: .atomic)
        } catch {
            logger.error("Failed to save lists: \(error.localizedDescription)")
        }
    }

    /// Persist all data (tasks + lists). Call after direct item mutations.
    func persist() {
        saveTasks()
        saveLists()
    }

    /// Persist tasks, lists, and labels together. Use after bulk mutations
    /// such as import where all three collections may have changed.
    func persistAll() {
        saveTasks()
        saveLists()
        saveLabels()
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
        mutator(&items[i])
        saveTasks()
        return true
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

    private func saveLabels() {
        guard labelsWritable else {
            logger.warning("Skipping labels save — writes are disabled after a failed corrupt-file backup")
            return
        }
        do {
            try JSONEncoder().encode(labels).write(to: labelsURL, options: .atomic)
        } catch {
            logger.error("Failed to save labels: \(error.localizedDescription)")
        }
    }

    // MARK: - Reminders Sync

    private func syncPush(_ item: TodoItem) {
        guard UserDefaults.standard.bool(forKey: "remindersSyncEnabled") else { return }
        let list = lists.first(where: { $0.id == item.listId })
        RemindersSync.shared.pushTask(item, calendarId: list?.remindersCalendarId)
    }
}
