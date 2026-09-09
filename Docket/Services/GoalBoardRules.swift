import Foundation
import AppKit

enum GoalBoardRules {
    static func ordered(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    static func featured(in items: [TodoItem], preferredID: String?) -> TodoItem? {
        if preferredID == "none" { return nil }
        let candidates = ordered(items.filter { !$0.isCompleted && $0.isPinned })
        return candidates.first { $0.id.uuidString == preferredID } ?? candidates.first
    }
    static func menuTitle(_ title: String, maxWidth: CGFloat = 190) -> String {
        let clean = title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let font = NSFont.menuBarFont(ofSize: 13)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        guard width(clean) > maxWidth || clean.count > 30 else { return clean }
        var result = String(clean.prefix(29))
        while !result.isEmpty && width(result + "…") > maxWidth { result.removeLast() }
        return result + "…"
    }
    static func panelSize(availableHeight: CGFloat) -> NSSize {
        NSSize(width: 408, height: min(560, max(210, availableHeight - 60)))
    }
}

enum DocketRuntime {
    /// Explicit local acceptance output. Omitted in normal launches.
    static var verificationDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--verification-output"), args.indices.contains(index + 1), args[index + 1].hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static let previewDirectory: URL? = {
        let args = ProcessInfo.processInfo.arguments
        guard isPreview else { return nil }
        guard let i = args.firstIndex(of: "--preview-data"), args.indices.contains(i + 1),
              args[i + 1].hasPrefix("/") else {
            fatalError("Polaris Preview requires --preview-data with an absolute path; real data is never used.")
        }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }()
    static var isPreview: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true }
}

extension Notification.Name {
    static let goalBoardChanged = Notification.Name("goalBoardChanged")
}
