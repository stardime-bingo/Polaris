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
        let dataURL = root.appendingPathComponent("tasks.json")
        try FileManager.default.removeItem(at: dataURL)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: false)
        check(!store.toggleStep(goalID: goal.id, stepID: goal.steps[1].id), "persistence failure is reported")
        check(store.items[0] == original && store.lastPersistenceError != nil, "failed write rolls back the visible checkbox")
        print("\(checks) step persistence checks passed")
    }
}
