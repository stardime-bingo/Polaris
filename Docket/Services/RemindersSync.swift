// Two-way reminders sync. The coordinator owns ordering and permissions;
// the backend carries value snapshots and is replaceable in isolated tests.
import Foundation
import Observation
import EventKit
import os

struct ReminderRecord {
    var id: String
    var calendarId: String
    var title: String
    var notes: String
    var priority: Int
    var completedAt: Date?
    var due: DateComponents?
    var modifiedAt: Date?
    var rules: [ReminderRecurrenceRule]
}

enum ReminderSyncFailure: LocalizedError {
    case cancelled, missingCalendar, remoteMissing, fetchFailed, persistence(String), unsupportedRule
    var errorDescription: String? {
        switch self {
        case .cancelled: "同步已暂停或列表绑定已更改，请重新同步。"
        case .missingCalendar: "提醒事项列表不可用或不可写。"
        case .remoteMissing: "远端提醒事项已删除；请先同步远端更改。"
        case .fetchFailed: "无法读取提醒事项，未修改本地数据。"
        case .persistence(let message): message
        case .unsupportedRule: "该 Apple 重复规则无法重新创建，原规则已保留。"
        }
    }
}

/// Callbacks run on main. Backends must check `valid` immediately before a
/// write, not just when it was queued. A commit already underway cannot be
/// revoked by EventKit; the coordinator never acknowledges it as a new sync
/// after its permission scope has changed.
protocol ReminderSyncBackend: AnyObject {
    func fetch(calendarId: String, completion: @escaping (Result<[ReminderRecord], Error>) -> Void)
    func save(_ item: TodoItem, calendarId: String, valid: @escaping () -> Bool, completion: @escaping (Result<ReminderRecord, Error>) -> Void)
    func remove(id: String, calendarId: String, valid: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void)
}

final class EventKitReminderBackend: ReminderSyncBackend {
    let eventStore = EKEventStore()
    private let queue = DispatchQueue(label: "com.bingowu.polaris.reminders-sync")

    static func record(_ reminder: EKReminder) -> ReminderRecord {
        ReminderRecord(id: reminder.calendarItemIdentifier, calendarId: reminder.calendar.calendarIdentifier,
            title: reminder.title ?? "Untitled", notes: reminder.notes ?? "", priority: reminder.priority,
            completedAt: reminder.isCompleted ? reminder.completionDate ?? Date() : nil,
            due: reminder.dueDateComponents, modifiedAt: reminder.lastModifiedDate,
            rules: (reminder.recurrenceRules ?? []).map { rule in
                ReminderRecurrenceRule(frequency: rule.frequency.rawValue, interval: rule.interval,
                    calendarIdentifier: rule.calendarIdentifier,
                    weekdays: (rule.daysOfTheWeek ?? []).map { .init(day: $0.dayOfTheWeek.rawValue, week: $0.weekNumber) },
                    monthDays: (rule.daysOfTheMonth ?? []).map(\.intValue), months: (rule.monthsOfTheYear ?? []).map(\.intValue),
                    weeks: (rule.weeksOfTheYear ?? []).map(\.intValue), yearDays: (rule.daysOfTheYear ?? []).map(\.intValue),
                    positions: (rule.setPositions ?? []).map(\.intValue), endDate: rule.recurrenceEnd?.endDate,
                    occurrenceCount: rule.recurrenceEnd?.occurrenceCount ?? 0)
            })
    }

    static func dueComponents(_ item: TodoItem) -> DateComponents? {
        guard let due = item.dueDate else { return nil }
        var calendar = Calendar.current
        if let zone = item.reminderDueTimeZoneID.flatMap(TimeZone.init(identifier:)) { calendar.timeZone = zone }
        let fields: Set<Calendar.Component> = item.hasDueTime ? [.year, .month, .day, .hour, .minute, .second] : [.year, .month, .day]
        var components = calendar.dateComponents(fields, from: due)
        components.calendar = calendar
        // Date-only reminders are floating calendar days, never midnight appointments.
        if item.hasDueTime { components.timeZone = calendar.timeZone }
        return components
    }

    static func makeRule(_ rule: ReminderRecurrenceRule) throws -> EKRecurrenceRule {
        func valid(_ values: [Int], _ range: ClosedRange<Int>, zeroAllowed: Bool = false) -> Bool {
            values.allSatisfy { range.contains($0) && (zeroAllowed || $0 != 0) }
        }
        guard let frequency = EKRecurrenceFrequency(rawValue: rule.frequency), rule.interval > 0,
              rule.calendarIdentifier == nil || rule.calendarIdentifier == "gregorian",
              rule.occurrenceCount >= 0,
              rule.weekdays.allSatisfy({ (1...7).contains($0.day) && (-53...53).contains($0.week) }),
              valid(rule.monthDays, -31...31), valid(rule.months, 1...12), valid(rule.weeks, -53...53),
              valid(rule.yearDays, -366...366), valid(rule.positions, -366...366) else { throw ReminderSyncFailure.unsupportedRule }
        let end: EKRecurrenceEnd?
        if let date = rule.endDate { end = EKRecurrenceEnd(end: date) }
        else if rule.occurrenceCount > 0 { end = EKRecurrenceEnd(occurrenceCount: rule.occurrenceCount) }
        else { end = nil }
        func numbers(_ values: [Int]) -> [NSNumber]? { values.isEmpty ? nil : values.map { NSNumber(value: $0) } }
        let days = rule.weekdays.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0.day)!, weekNumber: $0.week) }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: rule.interval,
            daysOfTheWeek: days.isEmpty ? nil : days, daysOfTheMonth: numbers(rule.monthDays),
            monthsOfTheYear: numbers(rule.months), weeksOfTheYear: numbers(rule.weeks),
            daysOfTheYear: numbers(rule.yearDays), setPositions: numbers(rule.positions), end: end)
    }

    func fetch(calendarId: String, completion: @escaping (Result<[ReminderRecord], Error>) -> Void) {
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else { completion(.failure(ReminderSyncFailure.missingCalendar)); return }
        eventStore.fetchReminders(matching: eventStore.predicateForReminders(in: [calendar])) { reminders in
            DispatchQueue.main.async {
                guard let reminders else { completion(.failure(ReminderSyncFailure.fetchFailed)); return }
                completion(.success(reminders.map { Self.record($0) }))
            }
        }
    }

    func save(_ item: TodoItem, calendarId: String, valid: @escaping () -> Bool, completion: @escaping (Result<ReminderRecord, Error>) -> Void) {
        queue.async { [self] in
            let result: Result<ReminderRecord, Error>
            do {
                guard DispatchQueue.main.sync(execute: valid) else { throw ReminderSyncFailure.cancelled }
                guard let calendar = eventStore.calendar(withIdentifier: calendarId), calendar.allowsContentModifications else { throw ReminderSyncFailure.missingCalendar }
                let reminder: EKReminder
                if let id = item.reminderId {
                    guard let existing = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { throw ReminderSyncFailure.remoteMissing }
                    let expected = item.reminderCalendarId ?? calendarId
                    guard existing.calendar.calendarIdentifier == expected || existing.calendar.calendarIdentifier == calendarId else { throw ReminderSyncFailure.cancelled }
                    reminder = existing
                    // A remote edit made since the fetch wins this conflict.
                    if let modified = existing.lastModifiedDate, modified > (item.lastSyncedAt ?? .distantPast) {
                        result = .success(Self.record(existing))
                        DispatchQueue.main.async { completion(result) }
                        return
                    }
                } else { reminder = EKReminder(eventStore: eventStore) }
                var replacementRules: [EKRecurrenceRule]?
                if item.reminderRecurrenceWasEdited == true { replacementRules = [] }
                else if item.reminderId == nil, let rules = item.remoteRecurrenceRules { replacementRules = try rules.map { try Self.makeRule($0) } }
                guard DispatchQueue.main.sync(execute: valid) else { throw ReminderSyncFailure.cancelled }
                reminder.calendar = calendar
                reminder.title = item.title
                reminder.notes = item.notes.isEmpty ? nil : item.notes
                reminder.priority = Self.priorityToEK(item.priority)
                reminder.dueDateComponents = Self.dueComponents(item)
                if let replacementRules {
                    reminder.recurrenceRules?.forEach { reminder.removeRecurrenceRule($0) }
                    replacementRules.forEach { reminder.addRecurrenceRule($0) }
                }
                // Preserve Apple-owned rules for ordinary edits; Apple creates
                // its own next occurrence when the reminder is completed.
                reminder.isCompleted = item.isCompleted
                reminder.completionDate = item.completedAt
                try eventStore.save(reminder, commit: true)
                result = .success(Self.record(reminder))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func remove(id: String, calendarId: String, valid: @escaping () -> Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            let result: Result<Void, Error>
            do {
                guard DispatchQueue.main.sync(execute: valid) else { throw ReminderSyncFailure.cancelled }
                if let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
                    guard reminder.calendar.calendarIdentifier == calendarId, reminder.calendar.allowsContentModifications else { throw ReminderSyncFailure.cancelled }
                    guard DispatchQueue.main.sync(execute: valid) else { throw ReminderSyncFailure.cancelled }
                    try eventStore.remove(reminder, commit: true)
                }
                result = .success(())
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func priorityToEK(_ priority: Priority) -> Int { switch priority { case .high: 1; case .medium: 5; case .low: 9 } }
}

@Observable
final class RemindersSync {
    static let shared = RemindersSync()
    var isAuthorized = false
    var lastSyncDate: Date?
    var lastError: String?
    private(set) var isSyncing = false
    @ObservationIgnored private let backend: ReminderSyncBackend
    @ObservationIgnored private let injectedStore: Store?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isTestBackend: Bool
    @ObservationIgnored private var changeObserver: Any?
    @ObservationIgnored private var debounce: DispatchWorkItem?
    private var generation = 0
    @ObservationIgnored private var operations: [(@escaping () -> Void) -> Void] = []
    private var operationRunning = false
    private var refreshQueued = false

    private var local: Store { injectedStore ?? Store.shared }
    private var liveBackend: EventKitReminderBackend? { backend as? EventKitReminderBackend }
    private var enabled: Bool { (isTestBackend || !DocketRuntime.isPreview) && isAuthorized && defaults.bool(forKey: "remindersSyncEnabled") }

    init(backend: ReminderSyncBackend? = nil, localStore: Store? = nil, defaults: UserDefaults = .standard) {
        self.backend = backend ?? EventKitReminderBackend()
        self.injectedStore = localStore
        self.defaults = defaults
        self.isTestBackend = backend != nil
        if backend != nil { isAuthorized = true } else { checkAccess() }
    }

    func checkAccess() {
        guard !DocketRuntime.isPreview else { isAuthorized = false; return }
        isAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestAccess() async -> Bool {
        guard !DocketRuntime.isPreview, let liveBackend else { return false }
        do {
            isAuthorized = try await liveBackend.eventStore.requestFullAccessToReminders()
            if !isAuthorized { lastError = "未获得提醒事项的完整访问权限。" }
            return isAuthorized
        } catch { isAuthorized = false; lastError = error.localizedDescription; return false }
    }

    func availableCalendars() -> [EKCalendar] {
        guard !DocketRuntime.isPreview, isAuthorized, let liveBackend else { return [] }
        return liveBackend.eventStore.calendars(for: .reminder).filter(\.allowsContentModifications)
    }

    func findOrCreateDocketCalendar() -> EKCalendar? { findOrCreateCalendar(named: "Docket") }
    func findOrCreateCalendar(named name: String) -> EKCalendar? {
        guard !DocketRuntime.isPreview, isAuthorized, let liveBackend else { return nil }
        if let existing = availableCalendars().first(where: { $0.title == name }) { return existing }
        let calendar = EKCalendar(for: .reminder, eventStore: liveBackend.eventStore)
        calendar.title = name
        calendar.source = liveBackend.eventStore.defaultCalendarForNewReminders()?.source
        do { try liveBackend.eventStore.saveCalendar(calendar, commit: true); return calendar }
        catch { lastError = error.localizedDescription; return nil }
    }

    private func valid(listId: UUID?, calendarId: String, generation: Int) -> Bool {
        enabled && self.generation == generation && local.lists.contains { $0.id == listId && $0.remindersCalendarId == calendarId }
    }

    private func enqueue(_ operation: @escaping (@escaping () -> Void) -> Void) {
        operations.append(operation)
        drain()
    }

    private func drain() {
        guard !operationRunning, !operations.isEmpty else { return }
        operationRunning = true
        let operation = operations.removeFirst()
        operation { [weak self] in
            guard let self else { return }
            self.operationRunning = false
            // Always schedule the next operation, avoiding recursion for mocks
            // and ensuring a pending toggle/unbind gets to invalidate it.
            DispatchQueue.main.async { self.drain() }
        }
    }

    private func report(_ result: Result<Void, Error>) {
        if case .failure(let error) = result { lastError = error.localizedDescription }
    }

    func pushTask(_ item: TodoItem, calendarId: String?, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard enabled, let calendarId else { completion?(.failure(ReminderSyncFailure.cancelled)); return }
        let token = generation
        enqueue { [weak self] done in
            guard let self else { done(); return }
            guard self.valid(listId: item.listId, calendarId: calendarId, generation: token),
                  let current = self.local.items.first(where: { $0.id == item.id && $0.listId == item.listId }) else {
                completion?(.failure(ReminderSyncFailure.cancelled)); done(); return
            }
            if current.reminderId != nil, current.reminderCalendarId == calendarId,
               (current.localModifiedAt ?? .distantPast) <= (current.lastSyncedAt ?? .distantPast) {
                completion?(.success(())); done(); return
            }
            self.performPush(current, calendarId: calendarId, generation: token) { result in
                self.report(result); completion?(result); done()
            }
        }
    }

    private func performPush(_ snapshot: TodoItem, calendarId: String, generation token: Int, retryMigration: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
        // For migration, both calendars must still be explicitly bound.
        let origin = snapshot.reminderCalendarId ?? calendarId
        let isValid = { [weak self] in
            guard let self else { return false }
            return self.valid(listId: snapshot.listId, calendarId: calendarId, generation: token)
                && self.local.lists.contains(where: { $0.remindersCalendarId == origin })
                && self.local.items.contains(where: { $0.id == snapshot.id && $0.listId == snapshot.listId && $0.localModifiedAt == snapshot.localModifiedAt && $0.reminderId == snapshot.reminderId })
        }
        guard isValid() else { completion(.failure(ReminderSyncFailure.cancelled)); return }
        backend.save(snapshot, calendarId: calendarId, valid: isValid) { [weak self] result in
            guard let self else { completion(.failure(ReminderSyncFailure.cancelled)); return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let record):
                // Retain the identity of an already-committed create even if an
                // edit/toggle raced its callback, preventing a duplicate create.
                guard let index = self.local.items.firstIndex(where: { $0.id == snapshot.id }) else {
                    if self.valid(listId: snapshot.listId, calendarId: calendarId, generation: token) {
                        var orphan = snapshot; orphan.reminderId = record.id; orphan.reminderCalendarId = record.calendarId
                        self.deleteReminder(for: orphan)
                    }
                    completion(.failure(ReminderSyncFailure.cancelled)); return
                }
                let before = self.local.items
                let scopeValid = self.valid(listId: snapshot.listId, calendarId: calendarId, generation: token)
                let unchanged = self.local.items[index].localModifiedAt == snapshot.localModifiedAt && self.local.items[index].listId == snapshot.listId
                self.local.items[index].reminderId = record.id
                self.local.items[index].reminderCalendarId = record.calendarId
                var spawned: [TodoItem] = []
                if scopeValid && unchanged {
                    if let next = self.applyRemoteChange(record, at: index, acknowledgedAt: Date(), protectSemanticEdit: snapshot.reminderId != nil) {
                        spawned.append(next)
                    }
                    self.local.items[index].reminderRecurrenceWasEdited = nil
                }
                guard self.local.persist() else {
                    self.local.items = before
                    completion(.failure(ReminderSyncFailure.persistence(self.local.lastPersistenceError ?? "同步标记保存失败。"))); return
                }
                guard scopeValid else { completion(.failure(ReminderSyncFailure.cancelled)); return }
                if unchanged { self.reconcileSideEffects(after: before, spawned: spawned) }
                if unchanged && record.calendarId != calendarId {
                    guard retryMigration else { completion(.failure(ReminderSyncFailure.cancelled)); return }
                    self.performPush(self.local.items[index], calendarId: calendarId, generation: token, retryMigration: false, completion: completion)
                    return
                }
                if !unchanged, let current = self.local.items.first(where: { $0.id == snapshot.id }),
                   let destination = self.local.lists.first(where: { $0.id == current.listId })?.remindersCalendarId {
                    self.pushTask(current, calendarId: destination)
                }
                completion(.success(()))
            }
        }
    }

    func deletionSnapshot(for item: TodoItem) -> TodoItem? {
        guard enabled, item.reminderId != nil,
              let currentCalendar = local.lists.first(where: { $0.id == item.listId })?.remindersCalendarId else { return nil }
        let origin = item.reminderCalendarId ?? currentCalendar
        guard let sourceList = local.lists.first(where: { $0.remindersCalendarId == origin }) else { return nil }
        var snapshot = item
        snapshot.listId = sourceList.id
        snapshot.reminderCalendarId = origin
        return snapshot
    }

    func deleteReminder(for item: TodoItem, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let snapshot = deletionSnapshot(for: item) else {
            completion?(.failure(ReminderSyncFailure.cancelled)); return
        }
        guard local.recordReminderDeletion(snapshot) else {
            let failure = ReminderSyncFailure.persistence(local.lastPersistenceError ?? "待同步删除保存失败。")
            lastError = failure.localizedDescription; completion?(.failure(failure)); return
        }
        let token = generation
        enqueue { [weak self] done in
            guard let self else { done(); return }
            self.performDelete(snapshot, generation: token) { result in self.report(result); completion?(result); done() }
        }
    }

    private func performDelete(_ item: TodoItem, generation token: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = item.reminderId, let calendarId = item.reminderCalendarId else { completion(.failure(ReminderSyncFailure.cancelled)); return }
        let isValid = { [weak self] in
            guard let self else { return false }
            return self.valid(listId: item.listId, calendarId: calendarId, generation: token)
                && !self.local.items.contains(where: { $0.reminderId == id })
        }
        guard isValid() else { completion(.failure(ReminderSyncFailure.cancelled)); return }
        backend.remove(id: id, calendarId: calendarId, valid: isValid) { [weak self] result in
            guard let self else { completion(.failure(ReminderSyncFailure.cancelled)); return }
            guard isValid() else { completion(.failure(ReminderSyncFailure.cancelled)); return }
            if case .success = result, !self.local.acknowledgeReminderDeletion(id) {
                completion(.failure(ReminderSyncFailure.persistence(self.local.lastPersistenceError ?? "删除同步标记保存失败。"))); return
            }
            completion(result)
        }
    }

    func pullChanges(for syncedLists: [TaskList], completion: ((Result<Void, Error>) -> Void)? = nil) {
        synchronize(lists: syncedLists, pushAfterMerge: false, completion: completion)
    }

    func syncAll(completion: ((Result<Void, Error>) -> Void)? = nil) {
        synchronize(lists: local.lists.filter { $0.remindersCalendarId != nil }, pushAfterMerge: true, completion: completion)
    }

    private func synchronize(lists: [TaskList], pushAfterMerge: Bool, completion: ((Result<Void, Error>) -> Void)?) {
        guard enabled else { completion?(.failure(ReminderSyncFailure.cancelled)); return }
        let bindings = lists.filter { $0.remindersCalendarId != nil }
        guard !bindings.isEmpty else { completion?(.success(())); return }
        let token = generation
        enqueue { [weak self] done in
            guard let self else { done(); return }
            self.isSyncing = true
            self.lastError = nil
            let finish: (Result<Void, Error>) -> Void = { result in
                self.isSyncing = false
                self.report(result)
                if case .success = result { self.lastSyncDate = Date() }
                completion?(result); done()
            }
            self.fetchAll(bindings, at: 0, generation: token, collected: []) { result in
                switch result {
                case .failure(let error): finish(.failure(error))
                case .success(let batches):
                    guard bindings.allSatisfy({ self.valid(listId: $0.id, calendarId: $0.remindersCalendarId!, generation: token) }) else { finish(.failure(ReminderSyncFailure.cancelled)); return }
                    guard self.merge(batches) else { finish(.failure(ReminderSyncFailure.persistence(self.local.lastPersistenceError ?? "保存远端更改失败。"))); return }
                    let pendingDeletes = self.local.pendingReminderDeletions.filter { item in
                        !self.local.items.contains(where: { $0.reminderId == item.reminderId }) &&
                        bindings.contains { $0.id == item.listId && $0.remindersCalendarId == item.reminderCalendarId }
                    }
                    self.deleteBatch(pendingDeletes, at: 0, generation: token) { result in
                        if case .failure = result { finish(result); return }
                        guard pushAfterMerge else { finish(.success(())); return }
                        // This snapshot is taken AFTER the remote merge, never before.
                        let pending = self.local.items.filter { item in
                            guard let binding = bindings.first(where: { $0.id == item.listId }) else { return false }
                            return item.reminderId == nil || item.reminderCalendarId != binding.remindersCalendarId
                                || (item.localModifiedAt ?? .distantPast) > (item.lastSyncedAt ?? .distantPast)
                        }
                        self.pushBatch(pending, at: 0, bindings: bindings, generation: token, completion: finish)
                    }
                }
            }
        }
    }

    private func fetchAll(_ bindings: [TaskList], at index: Int, generation token: Int, collected: [(TaskList, [ReminderRecord])], completion: @escaping (Result<[(TaskList, [ReminderRecord])], Error>) -> Void) {
        guard index < bindings.count else { completion(.success(collected)); return }
        let list = bindings[index], calendarId = bindings[index].remindersCalendarId!
        guard valid(listId: list.id, calendarId: calendarId, generation: token) else { completion(.failure(ReminderSyncFailure.cancelled)); return }
        backend.fetch(calendarId: calendarId) { result in
            guard self.valid(listId: list.id, calendarId: calendarId, generation: token) else { completion(.failure(ReminderSyncFailure.cancelled)); return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let records): self.fetchAll(bindings, at: index + 1, generation: token, collected: collected + [(list, records)], completion: completion)
            }
        }
    }

    private func deleteBatch(_ items: [TodoItem], at index: Int, generation: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < items.count else { completion(.success(())); return }
        performDelete(items[index], generation: generation) { result in
            if case .failure = result { completion(result); return }
            self.deleteBatch(items, at: index + 1, generation: generation, completion: completion)
        }
    }

    private func pushBatch(_ items: [TodoItem], at index: Int, bindings: [TaskList], generation: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < items.count else { completion(.success(())); return }
        let item = items[index]
        guard let current = local.items.first(where: { $0.id == item.id }),
              let calendarId = bindings.first(where: { $0.id == current.listId })?.remindersCalendarId else {
            pushBatch(items, at: index + 1, bindings: bindings, generation: generation, completion: completion); return
        }
        performPush(current, calendarId: calendarId, generation: generation) { result in
            if case .failure = result { completion(result); return }
            self.pushBatch(items, at: index + 1, bindings: bindings, generation: generation, completion: completion)
        }
    }

    /// Compare user-visible fields, ignoring identity/ack timestamps and the
    /// midnight normalization of floating date-only reminders. A real remote
    /// edit protects a generated successor from an immediate completion undo.
    private func hasSemanticDifference(_ record: ReminderRecord, from item: TodoItem) -> Bool {
        if record.title != item.title || record.notes != item.notes ||
            record.priority != EventKitReminderBackend.priorityToEK(item.priority) ||
            (record.completedAt != nil) != item.isCompleted || record.rules != (item.remoteRecurrenceRules ?? []) { return true }
        let expected = EventKitReminderBackend.dueComponents(item)
        guard let expected, let actual = record.due else { return (expected == nil) != (record.due == nil) }
        let actualHasTime = actual.hour != nil || actual.minute != nil || actual.second != nil
        if actualHasTime != item.hasDueTime { return true }
        if actual.year != expected.year || actual.month != expected.month || actual.day != expected.day { return true }
        return actualHasTime && (actual.hour != expected.hour || actual.minute != expected.minute || (actual.second ?? 0) != (expected.second ?? 0) || actual.timeZone != expected.timeZone)
    }

    private func apply(_ record: ReminderRecord, to item: inout TodoItem, acknowledgedAt: Date) {
        item.title = record.title; item.notes = record.notes
        item.priority = switch record.priority { case 1...4: .high; case 5...7: .medium; default: .low }
        item.completedAt = record.completedAt
        item.hasDueTime = record.due.map { $0.hour != nil || $0.minute != nil || $0.second != nil } ?? false
        if let components = record.due {
            var calendar = components.calendar ?? Calendar.current
            if let timezone = components.timeZone { calendar.timeZone = timezone }
            item.dueDate = calendar.date(from: components)
            item.reminderDueTimeZoneID = item.hasDueTime ? components.timeZone?.identifier : nil
        } else { item.dueDate = nil; item.reminderDueTimeZoneID = nil }
        if !record.rules.isEmpty {
            item.remoteRecurrenceRules = record.rules
            item.recurrence = record.rules.count == 1 ? record.rules.first?.simpleRecurrence : nil
        } else if item.hasRemoteRecurrence {
            item.remoteRecurrenceRules = nil; item.recurrence = nil
        }
        item.reminderId = record.id; item.reminderCalendarId = record.calendarId
        item.lastSyncedAt = acknowledgedAt
    }

    private func merge(_ batches: [(TaskList, [ReminderRecord])]) -> Bool {
        let before = local.items
        let allRemoteIDs = Set(batches.flatMap { $0.1.map(\.id) })
        let liveReminderIDs = Set(local.items.compactMap(\.reminderId))
        let tombstones = Set(local.pendingReminderDeletions.compactMap(\.reminderId)).subtracting(liveReminderIDs)
        let now = Date()
        var spawned: [TodoItem] = []
        for (list, records) in batches {
            for record in records where !tombstones.contains(record.id) {
                if let index = local.items.firstIndex(where: { $0.reminderId == record.id }) {
                    let current = local.items[index]
                    // A local move owns its destination until the migration commits.
                    guard current.listId == list.id else { continue }
                    let remoteChanged = (record.modifiedAt ?? .distantPast) > (current.lastSyncedAt ?? .distantPast)
                    let localDirty = (current.localModifiedAt ?? .distantPast) > (current.lastSyncedAt ?? .distantPast)
                    guard remoteChanged || current.lastSyncedAt == nil || (!localDirty && record.modifiedAt == nil) else {
                        if local.items[index].reminderCalendarId == nil { local.items[index].reminderCalendarId = record.calendarId }
                        continue
                    }
                    if let next = applyRemoteChange(record, at: index, acknowledgedAt: now) { spawned.append(next) }
                } else {
                    var item = TodoItem(title: record.title, listId: list.id)
                    apply(record, to: &item, acknowledgedAt: now)
                    item.sortOrder = (local.items.filter { $0.listId == list.id && !$0.isCompleted }.map(\.sortOrder).max() ?? -1) + 1
                    local.items.append(item)
                }
            }
            let calendarId = list.remindersCalendarId!
            local.items.removeAll { item in
                guard item.listId == list.id, let id = item.reminderId, !allRemoteIDs.contains(id) else { return false }
                // A destination fetch cannot delete a reminder still in its source calendar.
                if let origin = item.reminderCalendarId, origin != calendarId { return false }
                // EventKit only exposes the next incomplete Apple occurrence;
                // a completed native recurring reminder remains local history.
                if item.isCompleted && item.hasRemoteRecurrence { return false }
                return true
            }
        }
        guard local.persist() else { local.items = before; return false }
        reconcileSideEffects(after: before, spawned: spawned)
        return true
    }

    /// Both fetched records and save-conflict replies are remote observations.
    /// Apply their completion transition in memory before the caller commits
    /// the parent and successor together; no effects run before persistence.
    private func applyRemoteChange(_ record: ReminderRecord, at index: Int, acknowledgedAt: Date, protectSemanticEdit: Bool = true) -> TodoItem? {
        let previous = local.items[index]
        let semanticEdit = protectSemanticEdit && hasSemanticDifference(record, from: previous)
        apply(record, to: &local.items[index], acknowledgedAt: acknowledgedAt)
        if semanticEdit { local.items[index].localModifiedAt = acknowledgedAt }
        guard !previous.isCompleted, local.items[index].isCompleted else { return nil }
        return local.spawnRecurrenceIfNeeded(after: local.items[index])
    }

    /// Called only after a successful local commit. Remote due/title changes
    /// arriving through save conflicts need the same notification refresh as
    /// pulls; newly generated local occurrences enter the normal push queue.
    private func reconcileSideEffects(after before: [TodoItem], spawned: [TodoItem]) {
        let newIDs = Set(local.items.map(\.id))
        for item in before where !newIDs.contains(item.id) { local.cancelReminder(item) }
        for item in local.items where before.first(where: { $0.id == item.id }) != item {
            if item.isCompleted { local.cancelReminder(item) } else { local.scheduleReminder(item) }
        }
        for item in spawned {
            let calendarId = local.lists.first(where: { $0.id == item.listId })?.remindersCalendarId
            pushTask(item, calendarId: calendarId)
        }
    }

    func startObserving() {
        guard enabled, changeObserver == nil, let liveBackend else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: liveBackend.eventStore, queue: .main) { [weak self] _ in self?.remoteDidChange() }
    }

    /// Coalesce notifications, including self writes. There is no time window
    /// that discards genuine remote changes; unchanged pulls never write back.
    func remoteDidChange() {
        guard enabled else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, !self.refreshQueued else { return }
            self.refreshQueued = true
            self.pullChanges(for: self.local.lists.filter { $0.remindersCalendarId != nil }) { _ in self.refreshQueued = false }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func stopObserving() {
        generation += 1
        debounce?.cancel(); debounce = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver); self.changeObserver = nil }
    }
}
