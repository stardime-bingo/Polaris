import SwiftUI

struct GoalEditorView: View {
    @Binding var path: [NavDestination]
    @State private var draft: TodoItem
    private let editorID: UUID
    private let original: TodoItem
    private let isNew: Bool
    private let initiallyFeatured: Bool
    @State private var featured: Bool
    @State private var stepEntry = ""
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @FocusState private var titleFocused: Bool
    @Environment(\.polarisPalette) private var palette
    @Environment(PolarisPresentation.self) private var presentation
    init(item: TodoItem? = nil, path: Binding<[NavDestination]>, editorID: UUID) {
        _path = path
        self.editorID = editorID
        isNew = item == nil
        var value = item ?? TodoItem(title: "", dueDate: GoalPeriod.end(of: .month), reminderOffset: ReminderOffset(rawValue: UserDefaults.standard.object(forKey: "defaultReminderOffset") as? Int ?? 0) ?? .none)
        if item == nil {
            let filter = GoalFilter(rawValue: UserDefaults.standard.string(forKey: "goalFilter") ?? "all") ?? .all
            value = GoalScheduleRules.changingPeriod(value, to: filter == .week ? .week : filter == .year ? .year : filter == .longTerm ? .longTerm : .month)
        }
        original = value
        _draft = State(initialValue: value)
        initiallyFeatured = item != nil && Store.shared.menuBarGoal?.id == item?.id
        _featured = State(initialValue: initiallyFeatured)
    }
    private var cleanTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dirty: Bool { draft != original || featured != initiallyFeatured || !stepEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isActiveEditor: Bool { path.last?.editorID == editorID }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消", action: cancel)
                    .frame(minWidth: 48, minHeight: 32).contentShape(Rectangle())
                    .buttonStyle(.plain).foregroundStyle(palette.secondary)
                Spacer()
                Text(isNew ? "新建目标" : "编辑目标").font(.system(size: 12.5, weight: .medium))
                Spacer()
                Button(action: save) {
                    Text("保存").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.actionText).frame(width: 52, height: 32).contentShape(Rectangle())
                }.buttonStyle(GoalControlStyle(primary: true)).disabled(cleanTitle.isEmpty)
            }.font(.system(size: 12)).padding(.horizontal, 14).frame(height: 48)
            palette.line.frame(height: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("你想达成什么？", text: $draft.title, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 17, weight: .medium))
                            .lineSpacing(4).lineLimit(1...6).focused($titleFocused).accessibilityLabel("目标名称")
                        GoalEditorSection(title: "目标描述") {
                            TextField("补充目标背景、衡量标准或想法…", text: $draft.notes, axis: .vertical)
                                .textFieldStyle(.plain).font(.system(size: 12.5)).lineSpacing(4)
                                .foregroundStyle(palette.secondary).lineLimit(1...5)
                                .accessibilityLabel("目标描述")
                        }
                    }
                    GoalChecklistView(steps: $draft.steps, entry: $stepEntry,
                        syncEnabled: Store.shared.lists.first { $0.id == (draft.listId ?? Store.shared.activeListId) }?.remindersCalendarId != nil)
                    GoalEditorSection(title: "时间安排") { GoalTimingOptionsView(item: $draft, isActiveEditor: { isActiveEditor }) }
                    GoalEditorSection(title: "显示") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $draft.isPinned) { HStack { Text("置顶目标"); Spacer() } }
                                .frame(minHeight: 36)
                                .onChange(of: draft.isPinned) { _, value in if !value { featured = false } }
                            palette.line.frame(height: 0.5)
                            Toggle(isOn: $featured) { HStack { Text("在菜单栏显示"); Spacer() } }
                                .frame(minHeight: 36)
                                .onChange(of: featured) { _, value in if value { draft.isPinned = true } }
                        }.toggleStyle(.switch).controlSize(.small).tint(palette.action)
                            .font(.system(size: 12.5))
                    }
                    GoalEditorSection(title: "组织") { GoalOrganizationView(item: $draft) }
                    if !isNew {
                        VStack(spacing: 10) {
                            palette.line.frame(height: 0.5)
                            Button(action: complete) {
                                HStack(spacing: 9) {
                                    Image(systemName: "checkmark.circle").foregroundStyle(palette.secondary)
                                    Text("标记为已达成")
                                    Spacer()
                                }.font(.system(size: 12.5))
                                    .frame(maxWidth: .infinity, minHeight: 36).contentShape(Rectangle())
                            }.buttonStyle(GoalControlStyle()).foregroundStyle(palette.ink)
                            HStack {
                                Text("创建于 \(DueDateFormatter.format(draft.createdAt))")
                                    .font(.system(size: 10.5)).foregroundStyle(palette.muted)
                                Spacer()
                                Button("删除目标", role: .destructive) { confirmDelete = true }
                                    .font(.system(size: 11.5)).frame(minHeight: 32).contentShape(Rectangle()).buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.automatic)
        }
        .onAppear { trace("editor.appear"); if isNew { titleFocused = true } }
        .onChange(of: draft.listId) { _, listID in
            draft.labelIds.removeAll { id in !Store.shared.labels.contains(where: { $0.id == id && $0.listId == (listID ?? Store.shared.activeListId) }) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .polarisSave)) { _ in if isActiveEditor { save() } }
        .onReceive(NotificationCenter.default.publisher(for: .polarisEscape)) { _ in if isActiveEditor { cancel() } }
        .alert("放弃这次修改？", isPresented: $confirmDiscard) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive, action: dismiss)
        } message: { Text("尚未保存的内容会被丢弃。") }
        .confirmationDialog("删除这个目标？", isPresented: $confirmDelete) {
            Button("删除目标", role: .destructive) {
                guard isActiveEditor else { return }
                if Store.shared.delete(original) { dismiss() }
            }
            Button("取消", role: .cancel) {}
        }
    }
    private func complete() {
        guard isActiveEditor, !cleanTitle.isEmpty, persistDraft() else { return }
        NotificationCenter.default.post(name: .polarisComplete, object: draft)
        guard Store.shared.items.first(where: { $0.id == draft.id })?.isCompleted == true else { return }
        dismiss()
    }
    private func cancel() {
        trace("editor.cancel")
        guard isActiveEditor else { return }
        if dirty { confirmDiscard = true } else { dismiss() }
    }
    private func dismiss() {
        trace("editor.dismiss.before")
        guard isActiveEditor else { return }
        guard AppDelegate.shared?.endPanelEditing() ?? true else { return }
        titleFocused = false
        presentation.dismissCalendar()
        path.removeLast()
        trace("editor.dismiss.after")
    }
    private func save() {
        trace("editor.save.begin")
        guard isActiveEditor, !cleanTitle.isEmpty else { return }
        guard persistDraft() else { return }
        trace("editor.save.persisted")
        dismiss()
        NotificationCenter.default.post(name: .polarisSelectGoal, object: draft.id)
    }
    private func trace(_ event: String) {
        guard DocketRuntime.verificationDirectory != nil || DocketRuntime.isPreview else { return }
        AppDelegate.shared?.recordVerificationEvent(event, fields: [
            "root": String(describing: ObjectIdentifier(presentation)), "editorID": editorID.uuidString,
            "goalID": draft.id.uuidString, "active": isActiveEditor, "depth": path.count,
            "topEditorID": path.last?.editorID?.uuidString ?? "",
            "calendarOwnerID": presentation.calendarOwnerID?.uuidString ?? "", "titleEmpty": cleanTitle.isEmpty])
    }
    private func persistDraft() -> Bool {
        draft.title = cleanTitle
        let pendingStep = stepEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingStep.isEmpty { draft.steps.append(GoalStep(title: pendingStep)); stepEntry = "" }
        draft.steps = GoalStep.normalized(draft.steps)
        if draft.dueDate == nil {
            draft.hasDueTime = false; draft.recurrence = nil
            if original.dueDate != nil {
                draft.remoteRecurrenceRules = nil
                draft.reminderRecurrenceWasEdited = true
            }
        }
        let saved = isNew ? Store.shared.add(draft) : Store.shared.update(draft)
        guard saved else { return false }
        if featured && !initiallyFeatured { Store.shared.featureInMenuBar(draft) }
        else if !featured && initiallyFeatured { UserDefaults.standard.set("none", forKey: "menuBarGoalID"); NotificationCenter.default.post(name: .goalBoardChanged, object: nil) }
        return Store.shared.lastPersistenceError == nil
    }
}
