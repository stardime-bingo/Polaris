import Foundation

/// Each visit has its own editor identity, even when the same goal is opened twice.
enum NavDestination: Hashable {
    case create(editorID: UUID = UUID())
    case detail(TodoItem, editorID: UUID = UUID())
    case completed, settings, advancedSettings, matrix

    var editorID: UUID? {
        switch self {
        case .create(let id), .detail(_, let id): id
        default: nil
        }
    }
    var isEditor: Bool { editorID != nil }
}
