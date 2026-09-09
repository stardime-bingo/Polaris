import SwiftUI
struct CreateTaskView: View {
    @Binding var path: [NavDestination]
    let editorID: UUID
    var body: some View { GoalEditorView(path: $path, editorID: editorID) }
}
