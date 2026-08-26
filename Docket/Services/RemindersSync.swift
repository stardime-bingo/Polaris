// RemindersSync.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import Foundation
import os
import EventKit

/// Two-way sync between Docket and Apple Reminders via EventKit.
@Observable
final class RemindersSync {
    static let shared = RemindersSync()

    let store = EKEventStore()
    private let logger = Logger(subsystem: "blog.insecurity.docket", category: "reminders-sync")
    var isAuthorized = false
    var lastSyncDate: Date?

    private var changeObserver: Any?

    /// Serial queue for all EventKit writes so saves never block the main
    /// thread. This queue is used ONLY for the EventKit save/remove calls
    /// and does not gate reads of `_lastSelfWrite` — reading it from the
    /// main-queue observer callback used to `syncQueue.sync` back into a
    /// queue that could be busy (or, worse, waiting on the main thread via
    /// a completion block), which risks a deadlock. Access to
    /// `_lastSelfWrite` is guarded independently by `selfWriteLock` below.
    private let syncQueue = DispatchQueue(label: "blog.insecurity.docket.reminders-sync")

    /// Timestamp of our most recent programmatic EventKit write. Used to
    /// ignore the `.EKEventStoreChanged` notification that our own saves
    /// trigger. Access this ONLY through `getLastSelfWrite()` / `markSelfWrite()`
    /// so the read and write always happen under `selfWriteLock`. We use a
    /// plain non-recursive `NSLock` (not `syncQueue.sync`) so the main-queue
    /// EventKit observer never blocks on the write queue — the two now
    /// synchronise on a lock that neither ever holds across a queue hop.
    private var _lastSelfWrite: Date = .distantPast
    private let selfWriteLock = NSLock()

    private func markSelfWrite() {
        selfWriteLock.lock()
        _lastSelfWrite = Date()
        selfWriteLock.unlock()
    }

    /// Read the most recent self-write timestamp. Safe to call from any
    /// thread — including the main-queue EventKit change observer, which
    /// used to `syncQueue.sync` here and could deadlock against a pending
    /// EventKit save that dispatches back to the main queue.
    private func getLastSelfWrite() -> Date {
        selfWriteLock.lock()
        defer { selfWriteLock.unlock() }
        return _lastSelfWrite
    }

    init() {
        checkAccess()
    }

    // MARK: - Access

    func checkAccess() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        // Two-way sync both reads and writes reminders, so only full access is
        // sufficient. `.writeOnly` permits creating reminders but NOT reading
        // them, which would silently break the pull half of the sync.
        isAuthorized = status == .fullAccess
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    // MARK: - Calendars

    func availableCalendars() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .reminder)
    }

    func findOrCreateDocketCalendar() -> EKCalendar? {
        return findOrCreateCalendar(named: "Docket")
    }

    func findOrCreateCalendar(named name: String) -> EKCalendar? {
        guard isAuthorized else { return nil }
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == name }) {
            return existing
        }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = name
        cal.source = store.defaultCalendarForNewReminders()?.source
        do {
            try store.saveCalendar(cal, commit: true)
            markSelfWrite()
            return cal
        } catch { return nil }
    }

    // MARK: - Push (Docket → Reminders)

    /// Push a task to Reminders. When the caller needs to know that the
    /// reminderId has been assigned (e.g. syncAll wants to defer its pull
    /// until every push finishes), pass a `completion` — it fires on the
    /// main queue AFTER the id has been written back to Store.shared.
    func pushTask(_ item: TodoItem, calendarId: String?, completion: (() -> Void)? = nil) {
        guard isAuthorized, let calId = calendarId else {
            // Still signal completion so `syncAll` can move on even for
            // unsynced (calendar-less) tasks.
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }

        syncQueue.async { [weak self] in
            guard let self, let calendar = self.store.calendar(withIdentifier: calId) else {
                if let completion { DispatchQueue.main.async(execute: completion) }
                return
            }

            let reminder: EKReminder
            if let rid = item.reminderId, let existing = self.store.calendarItem(withIdentifier: rid) as? EKReminder {
                reminder = existing
            } else {
                reminder = EKReminder(eventStore: self.store)
                reminder.calendar = calendar
            }

            reminder.title = item.title
            reminder.notes = item.notes.isEmpty ? nil : item.notes
            reminder.priority = self.priorityToEK(item.priority)
            reminder.isCompleted = item.completedAt != nil
            reminder.completionDate = item.completedAt

            if let due = item.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            } else {
                reminder.dueDateComponents = nil
            }

            // Recurrence is managed entirely by Docket — it spawns the next
            // instance itself when a recurring task is completed. Pushing an
            // EKRecurrenceRule here would make Apple Reminders generate its *own*
            // occurrences too, producing duplicates. So we strip any existing
            // rule and never add one.
            reminder.recurrenceRules?.forEach { reminder.removeRecurrenceRule($0) }

            do {
                try self.store.save(reminder, commit: true)
                self.markSelfWrite()
                let newId = reminder.calendarItemIdentifier
                DispatchQueue.main.async {
                    if let i = Store.shared.items.firstIndex(where: { $0.id == item.id }) {
                        Store.shared.items[i].reminderId = newId
                        Store.shared.items[i].lastSyncedAt = Date()
                        Store.shared.persist()
                    }
                    completion?()
                }
            } catch {
                self.logger.error("Save reminder failed: \(error.localizedDescription)")
                if let completion { DispatchQueue.main.async(execute: completion) }
            }
        }
    }

    func deleteReminder(for item: TodoItem) {
        guard isAuthorized, let rid = item.reminderId else { return }
        syncQueue.async { [weak self] in
            guard let self,
                  let reminder = self.store.calendarItem(withIdentifier: rid) as? EKReminder else { return }
            try? self.store.remove(reminder, commit: true)
            self.markSelfWrite()
        }
    }

    // MARK: - Pull (Reminders → Docket)

    func pullChanges(for syncedLists: [TaskList]) {
        guard isAuthorized else { return }

        for list in syncedLists {
            guard let calId = list.remindersCalendarId,
                  let calendar = store.calendar(withIdentifier: calId) else { continue }

            let predicate = store.predicateForReminders(in: [calendar])
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // A nil callback result means the fetch itself failed (or
                    // was denied) — it is NOT the same as "no reminders exist".
                    // Skip the merge entirely so we don't perform destructive
                    // changes (removing locally-linked tasks) based on a fetch
                    // that never observed the remote state. An empty array,
                    // in contrast, IS a real observation: it must flow into
                    // merge so a legitimate "user deleted every reminder"
                    // propagates as a local delete.
                    guard let reminders else {
                        self.logger.warning("Nil fetch result for list '\(list.name)' — skipping merge (fetch failed or denied)")
                        return
                    }
                    self.mergeReminders(reminders, into: list)
                    self.lastSyncDate = Date()
                }
            }
        }
    }

    private func mergeReminders(_ reminders: [EKReminder], into list: TaskList) {
        let docketStore = Store.shared

        // NB: an empty `reminders` array is a legitimate observation — the
        // remote side has zero reminders in this calendar — and must flow
        // through the deletion path below so remote delete-all propagates
        // locally. The previous "empty fetch = keep locals" guard has been
        // removed; the callers of mergeReminders in this file only invoke it
        // with a *successful* fetch result (see pullChanges).

        for reminder in reminders {
            let rid = reminder.calendarItemIdentifier

            if let i = docketStore.items.firstIndex(where: { $0.reminderId == rid }) {
                // Existing — update if reminder is newer
                let local = docketStore.items[i]
                let remoteModified = reminder.lastModifiedDate ?? Date.distantPast
                let localSynced = local.lastSyncedAt ?? Date.distantPast
                guard remoteModified > localSynced else { continue }

                let becameCompleted = !local.isCompleted && reminder.isCompleted
                let becameActive = local.isCompleted && !reminder.isCompleted

                if becameCompleted {
                    // Route through the dedicated remote-completion path so
                    // the recurring-task spawn (and notification cancel) run
                    // exactly once — and we don't push the completion back.
                    let completionDate = reminder.completionDate ?? Date()
                    // Mirror non-completion field changes first so the
                    // to-be-archived item has the latest title/notes/etc.
                    docketStore.items[i].title = reminder.title ?? local.title
                    docketStore.items[i].notes = reminder.notes ?? ""
                    docketStore.items[i].priority = priorityFromEK(reminder.priority)
                    docketStore.items[i].dueDate = reminder.dueDateComponents?.date
                    docketStore.items[i].lastSyncedAt = Date()
                    docketStore.completeFromRemote(docketStore.items[i], at: completionDate)
                } else {
                    docketStore.items[i].title = reminder.title ?? local.title
                    docketStore.items[i].notes = reminder.notes ?? ""
                    docketStore.items[i].priority = priorityFromEK(reminder.priority)
                    docketStore.items[i].dueDate = reminder.dueDateComponents?.date
                    docketStore.items[i].completedAt = becameActive ? nil : local.completedAt
                    docketStore.items[i].lastSyncedAt = Date()
                    // A remote *active* update may have moved the due date;
                    // re-schedule the local notification so it fires on the
                    // new schedule (or is cancelled if the offset is .none).
                    NotificationManager.shared.scheduleReminder(for: docketStore.items[i])
                }
            } else {
                // New from Reminders — create in Docket
                var item = TodoItem(
                    title: reminder.title ?? "Untitled",
                    notes: reminder.notes ?? "",
                    priority: priorityFromEK(reminder.priority),
                    dueDate: reminder.dueDateComponents?.date,
                    listId: list.id
                )
                item.reminderId = rid
                item.lastSyncedAt = Date()
                item.completedAt = reminder.isCompleted ? (reminder.completionDate ?? Date()) : nil
                // Sort at the end of *this* list, independent of the currently
                // active list or label filter — otherwise a task pulled while
                // the user is viewing a filtered active list would collide
                // with existing sortOrder values.
                let siblings = docketStore.items.filter { !$0.isCompleted && $0.listId == list.id }
                item.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
                docketStore.items.append(item)
                if !item.isCompleted {
                    NotificationManager.shared.scheduleReminder(for: item)
                }
            }
        }

        // Remove tasks whose reminders were deleted remotely. Route through
        // the dedicated deletion path so notifications are cancelled and we
        // don't try to also delete the (already-gone) remote reminder.
        let reminderIds = Set(reminders.map(\.calendarItemIdentifier))
        let toRemove = docketStore.items.filter { item in
            item.listId == list.id && item.reminderId != nil && !reminderIds.contains(item.reminderId!)
        }
        for item in toRemove {
            docketStore.deleteFromRemote(item)
        }

        docketStore.persist()
    }

    // MARK: - Observe Changes

    func startObserving() {
        // Idempotent — repeated calls (e.g. from settings toggles) don't
        // stack observers, which would multiply pull work per remote change.
        if changeObserver != nil { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Ignore change notifications produced by our own recent writes —
            // otherwise every push triggers a full pull, which can feed back
            // into another push (an infinite sync loop). The timestamp is
            // read under `selfWriteLock` (never `syncQueue.sync`) so this
            // main-queue callback can't deadlock against a pending EventKit
            // save on the write queue.
            if Date().timeIntervalSince(self.getLastSelfWrite()) < 1.5 { return }
            let syncedLists = Store.shared.lists.filter { $0.remindersCalendarId != nil }
            self.pullChanges(for: syncedLists)
        }
    }

    func stopObserving() {
        if let obs = changeObserver {
            NotificationCenter.default.removeObserver(obs)
            changeObserver = nil
        }
    }

    // MARK: - Full Sync

    /// Push every synced Docket task and then pull remote state. The pull is
    /// deferred until every push completion callback has fired on the main
    /// thread — that means (a) every new reminder has been persisted to
    /// EventKit and (b) its identifier has been written back to
    /// `Store.shared.items[...].reminderId`. Without that ordering, the pull
    /// would see the freshly-created reminders as "new" (no matching
    /// reminderId locally), duplicate the task, and then leave the original
    /// pointing at a stale identifier.
    func syncAll() {
        let docketStore = Store.shared
        let syncedLists = docketStore.lists.filter { $0.remindersCalendarId != nil }

        // Collect tasks first so the count is stable across enumeration.
        var pending: [(item: TodoItem, calendarId: String?)] = []
        for list in syncedLists {
            let tasks = docketStore.items.filter { $0.listId == list.id }
            for task in tasks {
                pending.append((task, list.remindersCalendarId))
            }
        }

        if pending.isEmpty {
            pullChanges(for: syncedLists)
            return
        }

        var remaining = pending.count
        let done: () -> Void = { [weak self] in
            remaining -= 1
            if remaining == 0 {
                self?.pullChanges(for: syncedLists)
            }
        }

        for (task, calId) in pending {
            pushTask(task, calendarId: calId, completion: done)
        }
    }

    // MARK: - Helpers

    private func priorityToEK(_ p: Priority) -> Int {
        switch p { case .high: 1; case .medium: 5; case .low: 9 }
    }

    private func priorityFromEK(_ p: Int) -> Priority {
        switch p { case 1...4: .high; case 5...7: .medium; default: .low }
    }
}
