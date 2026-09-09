import Foundation

/// Validate and resolve relationships before changing the live store.
struct GoalImportPlan {
    let lists: [TaskList]
    let labels: [TaskLabel]
    let tasks: [TodoItem]
    let skipped: Int

    enum Failure: LocalizedError {
        case unsupportedVersion, invalidFormat, invalidRelationship
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "此文件来自更新版本，请先升级 Polaris。"
            case .invalidFormat: "文件不是有效的 Polaris 目标备份。"
            case .invalidRelationship: "文件包含重复标识、空标题或无效的目标集关联。"
            }
        }
    }

    init(data: Data, lists existingLists: [TaskList], labels existingLabels: [TaskLabel], tasks existingTasks: [TodoItem], activeListID: UUID, supportedVersion: Int) throws {
        let decoder = JSONDecoder()
        let export: DocketExport
        if let decoded = try? decoder.decode(DocketExport.self, from: data) { export = decoded }
        else if let decoded = try? decoder.decode([TodoItem].self, from: data) {
            export = DocketExport(lists: [], labels: [], tasks: decoded)
        } else { throw Failure.invalidFormat }
        guard (export.schemaVersion ?? 0) <= supportedVersion else { throw Failure.unsupportedVersion }
        guard Set(export.lists.map(\.id)).count == export.lists.count,
              Set(export.labels.map(\.id)).count == export.labels.count,
              Set(export.tasks.map(\.id)).count == export.tasks.count,
              export.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              export.tasks.allSatisfy({ item in
                  Set(item.steps.map(\.id)).count == item.steps.count &&
                  item.steps.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
              }),
              let fallback = existingLists.first(where: { $0.id == activeListID })?.id ?? existingLists.first?.id else { throw Failure.invalidRelationship }
        var allLists = existingLists
        var addedLists: [TaskList] = []
        var listMap: [UUID: UUID] = [:]
        for input in export.lists {
            guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidRelationship }
            if let match = allLists.first(where: { $0.id == input.id }) ?? allLists.first(where: { $0.name == input.name }) {
                listMap[input.id] = match.id
            } else {
                var value = input
                value.isDefault = false
                value.remindersCalendarId = nil
                listMap[input.id] = value.id
                allLists.append(value); addedLists.append(value)
            }
        }
        func resolvedList(_ id: UUID?) -> UUID {
            guard let id else { return fallback }
            return listMap[id] ?? (allLists.contains(where: { $0.id == id }) ? id : fallback)
        }
        var allLabels = existingLabels
        var addedLabels: [TaskLabel] = []
        var labelMap: [UUID: UUID] = [:]
        for input in export.labels {
            let listID = resolvedList(input.listId)
            if let match = allLabels.first(where: { $0.id == input.id && $0.listId == listID }) ?? allLabels.first(where: { $0.name == input.name && $0.listId == listID }) {
                labelMap[input.id] = match.id
            } else {
                var value = input
                value.listId = listID
                if allLabels.contains(where: { $0.id == value.id }) { value.id = UUID() }
                labelMap[input.id] = value.id
                allLabels.append(value); addedLabels.append(value)
            }
        }
        let existingIDs = Set(existingTasks.map(\.id))
        var addedTasks: [TodoItem] = []
        for input in export.tasks where !existingIDs.contains(input.id) {
            var value = input
            value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
            value.listId = resolvedList(input.listId)
            value.reminderId = nil // Never adopt another backup's Apple account binding.
            value.reminderCalendarId = nil
            value.lastSyncedAt = nil
            value.localModifiedAt = nil
            value.spawnedRecurrenceID = nil
            value.recurrenceParentID = nil
            value.reminderRecurrenceWasEdited = nil
            value.labelIds = Array(Set(input.labelIds.compactMap { id in
                let mapped = labelMap[id] ?? id
                return allLabels.contains(where: { $0.id == mapped && $0.listId == value.listId }) ? mapped : nil
            }))
            addedTasks.append(value)
        }
        self.lists = addedLists; self.labels = addedLabels; self.tasks = addedTasks
        skipped = export.tasks.count - addedTasks.count
    }
}
