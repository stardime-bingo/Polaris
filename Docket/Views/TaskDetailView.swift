import SwiftUI
struct TaskDetailView: View {
    let item: TodoItem
    @Binding var path: [NavDestination]
    let editorID: UUID
    var body: some View { GoalEditorView(item: item, path: $path, editorID: editorID) }
}
