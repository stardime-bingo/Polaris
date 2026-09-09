// Polaris — compact native goal list, following the frozen v5 design.
import SwiftUI
import AppKit

struct TaskListView: View {
    @Binding var path: [NavDestination]
    var store = Store.shared
    @AppStorage("goalFilter") private var filterRaw = GoalFilter.all.rawValue
    @AppStorage("panelShortcutsEnabled") private var localKeys = true
    @AppStorage("showConfetti") private var showConfetti = true
    @AppStorage("polarisMotionEnabled") private var motion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.polarisPalette) private var palette
    @Environment(\.polarisNow) private var now
    @Environment(PolarisPresentation.self) private var presentation
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var scrollRequest = 0
    @State private var focusGeneration = 0
    @State private var actionIndex = 0
    @State private var undoItem: TodoItem?
    @State private var showUndo = false
    @State private var undoTrigger = 0
    @State private var celebrationTrigger = 0
    private var filter: GoalFilter { GoalFilter(rawValue: filterRaw) ?? .all }
    private var items: [TodoItem] {
        let visible = store.activeTasks.filter { item in
            filter.includes(item, now: now) && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.notes.localizedCaseInsensitiveContains(search) || item.steps.contains { $0.title.localizedCaseInsensitiveContains(search) })
        }
        let mainID = store.menuBarGoal?.id
        return visible.filter { $0.id == mainID } + visible.filter { $0.id != mainID }
    }
    private var displayedItems: [TodoItem] { groups.flatMap { $0.2 } }
    private var selected: TodoItem? { items.first { $0.id == selectedID } ?? items.first }
    private var groups: [(String, String, [TodoItem])] {
        var result: [(String, String, [TodoItem])] = []
        let pins = items.filter(\.isPinned)
        if !pins.isEmpty { result.append(("置顶", "PINNED", pins)) }
        for period in GoalPeriod.allCases {
            let goals = items.filter { !$0.isPinned && $0.goalPeriod == period }
            if !goals.isEmpty { result.append((period.title + "目标", period.englishTitle, goals)) }
        }
        return result
    }
    private var actionsPresented: Binding<Bool> { Binding(get: { presentation.actionsArePresented }, set: { presentation.actionsArePresented = $0 }) }
    var body: some View {
        VStack(spacing: 0) {
            PolarisGlassGroup {
              HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .light)).foregroundStyle(palette.muted)
                PolarisSearchField(text: $search, placeholder: "搜索目标…", focusGeneration: focusGeneration,
                    onMove: moveSelection, onSubmit: editSelected, onEscape: escape, shortcutsEnabled: localKeys)
                    .frame(height: 25)
                Menu {
                    Picker("筛选目标", selection: $filterRaw) {
                        ForEach(GoalFilter.allCases) { Text(filterTitle($0)).tag($0.rawValue) }
                    }
                    if store.lists.count > 1 {
                        Divider()
                        ForEach(store.lists) { list in Button(list.name) { store.switchList(list) } }
                    }
                } label: { HStack(spacing: 5) { Text(filterTitle(filter)); Image(systemName: "chevron.down").font(.system(size: 8)) }.font(.system(size: 11)).foregroundStyle(palette.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(palette.secondary).accessibilityLabel("筛选目标")
              }.padding(.horizontal, 10).frame(height: 32).polarisGlassSurface()
            }.padding(.horizontal, 12).frame(height: 48)
            Rectangle().fill(palette.line).frame(height: 0.5)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        if items.isEmpty { emptyState }
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            PolarisSectionTitle(title: group.0)
                                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 3).frame(minHeight: 24)
                            ForEach(group.2) { item in
                                goalRow(item)
                            }
                        }
                    }.padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 7)
                }
                .onChange(of: scrollRequest) { _, _ in if let selectedID { proxy.scrollTo(selectedID) } }
            }
            Rectangle().fill(palette.line).frame(height: 0.5)
            footer
        }
        .overlay(alignment: .bottom) {
            UndoToast(message: "目标已达成", trigger: undoTrigger, onUndo: undo, isVisible: $showUndo).padding(.bottom, 38)
        }
        .overlay { ConfettiOverlay(trigger: celebrationTrigger, enabled: showConfetti && motion) }
        .onChange(of: showUndo) { _, value in presentation.canUndoCompletion = value }
        .onAppear { ensureSelection(); focusGeneration += 1 }
        .onChange(of: items.map(\.id)) { _, _ in ensureSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidOpen)) { _ in focusGeneration += 1; ensureSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .polarisSelectGoal)) { note in
            if let id = note.object as? UUID {
                if !items.contains(where: { $0.id == id }) { filterRaw = GoalFilter.all.rawValue; search = "" }
                selectedID = id
                scrollRequest += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .polarisComplete)) { note in if let item = note.object as? TodoItem { complete(item) } }
        .onReceive(NotificationCenter.default.publisher(for: .polarisCommand)) { note in
            guard path.isEmpty, let command = note.object as? String else { return }
            switch command {
            case "up": if presentation.actionsArePresented { actionIndex = max(0, actionIndex - 1) } else { moveSelection(-1) }
            case "down": if presentation.actionsArePresented { actionIndex = min(actionCount - 1, actionIndex + 1) } else { moveSelection(1) }
            case "edit": if presentation.actionsArePresented { performAction(actionIndex) } else { editSelected() }
            case "actions": actionIndex = 0; presentation.actionsArePresented.toggle()
            case "escape": escape()
            case "undo": if showUndo { undo(); showUndo = false }
            case "pin": if let selected { store.togglePin(selected) }
            case "complete": if let selected { complete(selected) }
            default: break
            }
        }
    }
    private func goalRow(_ item: TodoItem) -> some View {
        TaskRowView(item: item, onComplete: { complete(item) }, isSelected: selected?.id == item.id,
            onToggleStep: { stepID in
                withAnimation(motion && !reduceMotion ? .easeInOut(duration: 0.16) : nil) {
                    _ = store.toggleStep(goalID: item.id, stepID: stepID)
                }
            })
            .id(item.id)
            .onTapGesture(count: 2) { selectedID = item.id; editSelected() }
            .onTapGesture { selectedID = item.id }
            .onHover { if $0 { selectedID = item.id } }
            .contextMenu { rowActions(item) }
            .accessibilityActions {
                Button("编辑目标") { selectedID = item.id; editSelected() }
                Button(item.isPinned ? "取消置顶" : "置顶目标") { store.togglePin(item) }
                Button("标记已达成") { complete(item) }
                Button("上移") { move(item, by: -1) }.disabled(moveNeighbor(item, by: -1) == nil)
                Button("下移") { move(item, by: 1) }.disabled(moveNeighbor(item, by: 1) == nil)
            }
    }
    private func filterTitle(_ filter: GoalFilter) -> String { filter.title }
    private var footer: some View {
        PolarisFooter(isActive: path.isEmpty, onNew: { path.append(.create()) }, onEdit: editAction,
            onSettings: { path.append(.settings) },
            onActions: { actionIndex = 0; presentation.actionsArePresented.toggle() })
            .popover(isPresented: actionsPresented, arrowEdge: .bottom) { actionMenu }
    }
    private var editAction: (() -> Void)? {
        guard selected != nil else { return nil }
        return { editSelected() }
    }
    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(nsImage: PolarisSymbol.menuImage()).opacity(0.6)
            Text(search.isEmpty ? "留给重要的目标" : "没有匹配的目标").font(.system(size: 14))
            Text(search.isEmpty ? "写下第一件值得记住的事。" : "试试其他关键词。").font(.system(size: 12)).foregroundStyle(palette.muted)
            if search.isEmpty { Button("新建目标") { path.append(.create()) }.buttonStyle(.plain).foregroundStyle(palette.accentInk) }
        }.frame(maxWidth: .infinity).frame(height: 150)
    }
    private var actionCount: Int { selected == nil ? 1 : 5 }
    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selected?.title ?? "Polaris").font(.system(size: 11)).foregroundStyle(palette.muted).lineLimit(2).padding(10)
            if let item = selected {
                actionRow("编辑目标", "pencil", 0, "↵")
                actionRow(item.isPinned ? "取消置顶" : "置顶目标", "pin", 1, "⌘ P")
                actionRow(store.menuBarGoal?.id == item.id ? "从菜单栏移除" : "设为菜单栏主目标", "menubar.rectangle", 2, "")
                actionRow("标记已达成", "checkmark.circle", 3, "")
                Divider().padding(.vertical, 3)
            }
            actionRow("新建目标", "plus", actionCount - 1, "⌘ N")
        }.padding(6).frame(width: 270).background(palette.raised)
    }
    private func actionRow(_ title: String, _ icon: String, _ index: Int, _ shortcut: String) -> some View {
        Button { performAction(index) } label: {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 14); Text(title); Spacer(); if localKeys && !shortcut.isEmpty { PolarisKeycap(text: shortcut) } }
                .font(.system(size: 12.5)).foregroundStyle(palette.ink).padding(.horizontal, 9).frame(height: 34)
                .background(actionIndex == index ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).onHover { if $0 { actionIndex = index } }
    }
    private func performAction(_ index: Int) {
        presentation.actionsArePresented = false
        guard let selected, index < 4 else { path.append(.create()); return }
        switch index { case 0: editSelected(); case 1: store.togglePin(selected); case 2: feature(selected); case 3: complete(selected); default: break }
    }
    @ViewBuilder private func rowActions(_ item: TodoItem) -> some View {
        Button("编辑目标") { selectedID = item.id; editSelected() }
        Button(item.isPinned ? "取消置顶" : "置顶目标") { store.togglePin(item) }
        Button("设为菜单栏主目标") { store.featureInMenuBar(item) }
        Button("标记已达成") { complete(item) }
        Divider()
        Button("上移") { move(item, by: -1) }.disabled(moveNeighbor(item, by: -1) == nil); Button("下移") { move(item, by: 1) }.disabled(moveNeighbor(item, by: 1) == nil)
    }
    private func feature(_ item: TodoItem) {
        if store.menuBarGoal?.id == item.id { UserDefaults.standard.set("none", forKey: "menuBarGoalID"); NotificationCenter.default.post(name: .goalBoardChanged, object: nil) }
        else { store.featureInMenuBar(item) }
    }
    private func ensureSelection() { if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id } }
    private func moveSelection(_ offset: Int) {
        guard !items.isEmpty else { return }
        let ordered = displayedItems
        let index = ordered.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = ordered[min(ordered.count - 1, max(0, index + offset))].id
        scrollRequest += 1
    }
    private func moveNeighbor(_ item: TodoItem, by delta: Int) -> UUID? {
        let primaryID = store.menuBarGoal?.id
        guard item.id != primaryID,
              let group = groups.first(where: { $0.2.contains(where: { $0.id == item.id }) })?.2.filter({ $0.id != primaryID }),
              let index = group.firstIndex(where: { $0.id == item.id }),
              group.indices.contains(index + delta) else { return nil }
        return group[index + delta].id
    }
    private func move(_ item: TodoItem, by delta: Int) {
        // Move within the visible group; hidden goals and other periods keep their order.
        guard let neighborID = moveNeighbor(item, by: delta) else { return }
        var ids = store.activeTasks.map(\.id)
        guard let source = ids.firstIndex(of: item.id), let target = ids.firstIndex(of: neighborID) else { return }
        ids.swapAt(source, target); store.applyManualOrder(ids)
    }
    private func editSelected() { showUndo = false; presentation.canUndoCompletion = false; undoItem = nil; if let selected { presentation.actionsArePresented = false; path.append(.detail(selected)) } }
    private func escape() {
        if presentation.actionsArePresented { presentation.actionsArePresented = false }
        else if !search.isEmpty { search = "" }
        else { AppDelegate.shared?.closePopover() }
    }
    private func complete(_ item: TodoItem) {
        guard store.items.contains(where: { $0.id == item.id && !$0.isCompleted }) else { return }
        guard store.complete(item) else { return }
        undoItem = item; showUndo = true
        presentation.canUndoCompletion = true; undoTrigger += 1; celebrationTrigger += 1
    }
    private func undo() { presentation.canUndoCompletion = false; if let undoItem { store.undoCompletion(undoItem) }; undoItem = nil }
}
