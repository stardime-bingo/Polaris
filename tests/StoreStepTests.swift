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

        let dataURL = root.appendingPathComponent("tasks.json")
        try FileManager.default.removeItem(at: dataURL)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: false)
        check(!store.toggleStep(goalID: goal.id, stepID: goal.steps[1].id), "persistence failure is reported")
        check(store.items[0] == original && store.lastPersistenceError != nil, "failed write rolls back the visible checkbox")
        print("\(checks) step and matrix persistence checks passed")
    }
}
