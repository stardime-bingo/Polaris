import Foundation

// System notifications are deliberately unavailable to this persistence test.
final class NotificationManager {
    static let shared = NotificationManager()
    func scheduleReminder(for item: TodoItem) { fatalError("Unexpected notification") }
    func cancelReminder(for item: TodoItem) { fatalError("Unexpected notification") }
}

@main enum StoreStepTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PolarisStepTests-\(UUID())")
        let domain = "com.bingowu.polaris.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: domain) }
        let store = Store(directory: root, defaults: defaults, performsSideEffects: false)
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            guard value else { fatalError("FAIL: \(message)") }
            print("PASS: \(message)")
        }
        var goal = TodoItem(title: "Parent", steps: [GoalStep(title: "One"), GoalStep(title: "Two")])
        goal.listId = store.activeListId
        goal.notes = "Latest parent details"
        check(store.add(goal), "save initial goal")
        let original = store.items.first { $0.id == goal.id }!
        check(store.toggleStep(goalID: goal.id, stepID: goal.steps[0].id), "complete one step")
        var expected = original
        expected.steps[0].isCompleted = true
        check(store.items[0] == expected, "only the selected step changes; parent fields and identity are preserved")
        let reloaded = Store(directory: root, defaults: defaults, performsSideEffects: false)
        check(reloaded.items[0] == expected, "step state survives reloading the real JSON store")
        check(!store.items[0].isCompleted, "all step operations leave parent completion independent")
        check(store.toggleStep(goalID: goal.id, stepID: goal.steps[0].id), "uncheck the same step")
        check(store.items[0] == original, "toggle back restores the original goal exactly")
        check(!store.toggleStep(goalID: UUID(), stepID: goal.steps[0].id), "missing goal is ignored")
        check(!store.toggleStep(goalID: goal.id, stepID: UUID()), "deleted step is ignored")

        // Exercise the same mutation/persistence entry point as matrix drags,
        // then the editor update path. Classification must not become priority.
        let matrixRoot = root.appendingPathComponent("matrix")
        let matrixStore = Store(directory: matrixRoot, defaults: defaults, performsSideEffects: false)
        var matrixGoal = TodoItem(title: "Fictional matrix goal")
        matrixGoal.listId = matrixStore.activeListId
        matrixGoal.priority = .high
        matrixGoal.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        matrixGoal.hasDueTime = false
        matrixGoal.reminderId = "fictional-reminder"
        matrixGoal.reminderCalendarId = "fictional-calendar"
        check(matrixStore.add(matrixGoal), "save matrix fixture without external side effects")
        let matrixOriginal = matrixStore.items[0]
        check(matrixStore.mutate(matrixGoal.id) { $0.quadrant = .doFirst; $0.matrixX = 0.3; $0.matrixY = 0.6 }, "matrix drag uses the real Store.mutate")
        var matrixExpected = matrixOriginal
        matrixExpected.quadrant = .doFirst; matrixExpected.matrixX = 0.3; matrixExpected.matrixY = 0.6
        matrixExpected.localModifiedAt = matrixStore.items[0].localModifiedAt
        check(matrixStore.items[0] == matrixExpected, "matrix classification preserves priority, order, deadline and sync identity")
        let matrixReloaded = Store(directory: matrixRoot, defaults: defaults, performsSideEffects: false)
        check(matrixReloaded.items[0] == matrixExpected, "matrix placement survives real JSON reload")
        var edited = matrixReloaded.items[0]
        edited.quadrant = .schedule
        check(matrixReloaded.update(edited), "editor can change the same quadrant field")
        let editorReloaded = Store(directory: matrixRoot, defaults: defaults, performsSideEffects: false)
        check(editorReloaded.items[0].quadrant == .schedule && editorReloaded.items[0].priority == .high, "editor classification persists independently of priority")
        let beforeFailedDrag = editorReloaded.items
        let matrixURL = matrixRoot.appendingPathComponent("tasks.json")
        try FileManager.default.removeItem(at: matrixURL)
        try FileManager.default.createDirectory(at: matrixURL, withIntermediateDirectories: false)
        check(!editorReloaded.mutate(matrixGoal.id) { $0.quadrant = .eliminate }, "matrix write failure is reported")
        check(editorReloaded.items == beforeFailedDrag && editorReloaded.lastPersistenceError != nil, "failed matrix move rolls back visible classification")

        // Completion undo uses the production Store paths. Steps are local-only,
        // so a checked successor can still have its original modification time.
        let untouchedRoot = root.appendingPathComponent("recurrence-untouched")
        let untouchedStore = Store(directory: untouchedRoot, defaults: defaults, performsSideEffects: false)
        var recurring = TodoItem(title: "Fictional daily goal", steps: [GoalStep(title: "First step", isCompleted: true), GoalStep(title: "Second step")])
        recurring.listId = untouchedStore.activeListId
        recurring.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        recurring.recurrence = Recurrence(frequency: .daily, interval: 1, endDate: nil)
        check(untouchedStore.add(recurring), "save untouched recurrence fixture")
        check(untouchedStore.complete(recurring), "complete recurrence and persist its successor")
        let untouchedParent = untouchedStore.items.first { $0.id == recurring.id }!
        let untouchedChild = untouchedStore.items.first { $0.id == untouchedParent.spawnedRecurrenceID }!
        check(untouchedChild.recurrenceParentID == recurring.id && untouchedChild.steps.allSatisfy { !$0.isCompleted }, "successor starts linked with cleared step progress")
        check(untouchedStore.undoCompletion(recurring), "undo completion with an untouched successor")
        check(untouchedStore.items.count == 1 && untouchedStore.items[0].id == recurring.id && !untouchedStore.items[0].isCompleted, "untouched successor is removed and original occurrence restored")
        check(untouchedStore.items[0].spawnedRecurrenceID == nil && untouchedStore.items[0].steps == recurring.steps, "untouched undo clears the successor link and preserves original steps")
        let untouchedReloaded = Store(directory: untouchedRoot, defaults: defaults, performsSideEffects: false)
        check(untouchedReloaded.items == untouchedStore.items, "untouched undo survives real JSON reload")

        let progressedRoot = root.appendingPathComponent("recurrence-progressed")
        let progressedStore = Store(directory: progressedRoot, defaults: defaults, performsSideEffects: false)
        var progressedGoal = recurring
        progressedGoal.id = UUID()
        progressedGoal.listId = progressedStore.activeListId
        check(progressedStore.add(progressedGoal), "save progressed recurrence fixture")
        check(progressedStore.complete(progressedGoal), "complete original occurrence before checking successor step")
        let completedParent = progressedStore.items.first { $0.id == progressedGoal.id }!
        let freshChild = progressedStore.items.first { $0.id == completedParent.spawnedRecurrenceID }!
        check(freshChild.localModifiedAt == freshChild.createdAt, "fresh successor has unchanged parent-field timestamp")
        check(progressedStore.toggleStep(goalID: freshChild.id, stepID: freshChild.steps[0].id), "check a successor step through the real local-only toggle path")
        var expectedChild = freshChild
        expectedChild.steps[0].isCompleted = true
        check(progressedStore.items.first { $0.id == freshChild.id } == expectedChild, "successor checkbox preserves every parent field including timestamp and sync metadata")
        let beforeUndoReloaded = Store(directory: progressedRoot, defaults: defaults, performsSideEffects: false)
        check(beforeUndoReloaded.items.first { $0.id == freshChild.id } == expectedChild, "successor progress is on disk before undo")
        check(progressedStore.undoCompletion(progressedGoal), "undo completion after successor step progress")
        check(progressedStore.items.count == 2 && progressedStore.items.contains { $0.id == progressedGoal.id && !$0.isCompleted }, "progressed undo restores the original occurrence without deleting the successor")
        check(progressedStore.items.first { $0.id == freshChild.id } == expectedChild, "undo preserves successor identity, progress, timestamp and sync metadata exactly")
        let restoredParent = progressedStore.items.first { $0.id == progressedGoal.id }!
        check(restoredParent.spawnedRecurrenceID == freshChild.id && expectedChild.recurrenceParentID == restoredParent.id, "progressed undo keeps both sides of the recurrence association")
        let progressedReloaded = Store(directory: progressedRoot, defaults: defaults, performsSideEffects: false)
        check(progressedReloaded.items == progressedStore.items, "restored parent and progressed successor survive real JSON reload together")
        check(progressedReloaded.complete(restoredParent), "complete the restored occurrence again after reload")
        check(progressedReloaded.items.count == 2 && progressedReloaded.items.filter { $0.recurrenceParentID == progressedGoal.id }.count == 1, "recompletion does not create a duplicate successor")
        check(progressedReloaded.items.first { $0.id == progressedGoal.id }?.spawnedRecurrenceID == freshChild.id && progressedReloaded.items.first { $0.id == freshChild.id } == expectedChild, "recompletion retains the existing successor and its checked step")
        let recompletedReloaded = Store(directory: progressedRoot, defaults: defaults, performsSideEffects: false)
        check(recompletedReloaded.items == progressedReloaded.items, "recompletion and recurrence association remain consistent after reload")

        let dataURL = root.appendingPathComponent("tasks.json")
        try FileManager.default.removeItem(at: dataURL)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: false)
        check(!store.toggleStep(goalID: goal.id, stepID: goal.steps[1].id), "persistence failure is reported")
        check(store.items[0] == original && store.lastPersistenceError != nil, "failed write rolls back the visible checkbox")
        print("\(checks) step, matrix and recurrence undo persistence checks passed")
    }
}
