// SettingsView.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI
import AppKit
import EventKit
import ServiceManagement
import Carbon.HIToolbox
internal import UniformTypeIdentifiers

/// App preferences: reminders, hotkey, launch at login, theme.
struct SettingsView: View {
    @Binding var path: [NavDestination]
    var store = Store.shared

    @AppStorage("defaultReminderOffset") private var defaultOffset: Int = ReminderOffset.none.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("notifSound") private var notifSound = "default"
    @AppStorage("badgeAllLists") private var badgeAllLists = false
    @AppStorage("multiLineTask") private var multiLineTask = false
    @AppStorage("showConfetti") private var showConfetti = true
    @AppStorage("appTheme") private var themeRaw: Int = AppTheme.white.rawValue
    @AppStorage("customHue") private var customHue: Double = 0.55
    @AppStorage("customSat") private var customSat: Double = 0.3

    var body: some View {
        VStack(spacing: 0) {
            header
            palette.line.frame(height: 0.5)
            VScroll {
                ScrollViewReader { proxy in
                VStack(spacing: 12) {
                    groupHeader(L10n.groupGeneral, first: true)
                    generalSection

                    groupHeader(L10n.groupAppearance)
                    displaySection
                    matrixSection

                    groupHeader(L10n.groupNotifications)
                    reminderSection

                    groupHeader(L10n.groupOrganize)
                    listsSection
                    labelsSection

                    groupHeader(L10n.groupSyncData)
                    remindersSection
                    dataSection

                    #if !DOCKET_SELFBUILD
                    groupHeader(L10n.groupSupport)
                    card { TipJarView() }
                        .id("tipJar")
                    #endif

                    VStack(spacing: 4) {
                        Text("Polaris v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                            .font(.caption).foregroundStyle(.tertiary)
                        Link("基于 Docket 开源项目 · @santoru", destination: URL(string: "https://github.com/santoru/docket")!)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }
                .padding(20)
                .onReceive(NotificationCenter.default.publisher(for: .scrollToTipJar)) { _ in
                    withAnimation { proxy.scrollTo("tipJar", anchor: .bottom) }
                }
                } // ScrollViewReader
            }
        }
        .onAppear {
            if !DocketRuntime.isPreview {
                launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }
        }
        .alert("Polaris", isPresented: $showDataFeedback) { Button("好", role: .cancel) {} } message: { Text(dataFeedback ?? "") }
        .alert(L10n.deleteListTitle, isPresented: $showDeleteConfirm) {
            Button(L10n.delete, role: .destructive) {
                if let list = listToDelete { withAnimation { store.deleteList(list) } }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if let list = listToDelete {
                let count = store.items.filter { $0.listId == list.id }.count
                Text(L10n.deleteListMessage(list.name, count))
            }
        }
        .alert(L10n.clearCompletedTitle, isPresented: $showClearConfirm) {
            Button(L10n.clearNTasks(store.completedTasks.count), role: .destructive) {
                withAnimation { _ = store.clearCompleted() }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.clearCompletedMessage)
        }
        .alert(L10n.deleteLabelTitle, isPresented: $showLabelDeleteConfirm) {
            Button(L10n.delete, role: .destructive) {
                if let label = labelToDelete { withAnimation { store.deleteLabel(label) } }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if let label = labelToDelete {
                let count = store.items.filter { $0.labelIds.contains(label.id) }.count
                Text(L10n.deleteLabelMessage(label.name, count))
            }
        }
    }

    private var header: some View {
        HStack {
            Button { path.removeLast() } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(GoalControlStyle()).accessibilityLabel("返回设置")
            Spacer()
            Text("更多设置").font(.system(size: 12.5, weight: .medium))
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }.padding(.horizontal, 13).frame(height: 48)
    }

    // MARK: - Sections

    @Environment(\.polarisPalette) private var palette
    private var accent: Color { palette.accentInk }

    private var reminderSection: some View {
        card {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.defaultReminder)
                    Spacer()
                    Picker(L10n.defaultReminder, selection: $defaultOffset) {
                        ForEach(ReminderOffset.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }.labelsHidden()
                }.frame(minHeight: 36)
                palette.line.frame(height: 0.5)
                HStack {
                    Text(L10n.sound)
                    Spacer()
                    Picker(L10n.sound, selection: Binding(get: { notifSound }, set: setSound)) {
                        Text(L10n.soundDefault).tag("default")
                        ForEach(["Ping", "Glass", "Pop", "Purr", "Submarine", "Tink"], id: \.self) { Text($0).tag($0) }
                        Text(L10n.soundNone).tag("none")
                    }.labelsHidden()
                }.frame(minHeight: 36)
                palette.line.frame(height: 0.5)
                HStack {
                    Text("到期计数范围")
                    Spacer()
                    Picker("到期计数范围", selection: $badgeAllLists) {
                        Text(L10n.currentList).tag(false)
                        Text(L10n.allLists).tag(true)
                    }.labelsHidden()
                }.frame(minHeight: 36)
            }.font(.system(size: 12.5)).pickerStyle(.menu).controlSize(.small)
        }
    }

    private func setSound(_ sound: String) {
        notifSound = sound
        if sound != "none" {
            if sound == "default" {
                NSSound.beep()
            } else {
                NSSound(named: sound)?.play()
            }
        }
    }

    private var generalSection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                ThemedToggle(label: L10n.launchAtLogin, isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .disabled(DocketRuntime.isPreview)
                if !DocketRuntime.isPreview, SMAppService.mainApp.status == .requiresApproval {
                    Button("在系统设置中允许登录启动") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(accent)
                }
                palette.line.frame(height: 0.5)
                Text("标题自动换行，页面尺寸一致，长内容在面板内滚动。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard !DocketRuntime.isPreview else { return }
        if enabled {
            do {
                try SMAppService.mainApp.register()
                launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
                reportData("未能设置登录启动：\(error.localizedDescription)")
            }
        } else {
            SMAppService.mainApp.unregister { error in
                DispatchQueue.main.async {
                    launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
                    if let error { reportData("未能关闭登录启动：\(error.localizedDescription)") }
                }
            }
        }
    }

    // MARK: - Reminders Sync

    @AppStorage("remindersSyncEnabled") private var remindersSyncEnabled = false
    @State private var availableCalendars: [EKCalendar] = []
    @State private var syncedCalendarIds: Set<String> = []
    @State private var restoringSyncAccess = false

    private var remindersSection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.remindersSync).font(.system(size: 12.5, weight: .medium))
                ThemedToggle(label: L10n.syncWithReminders, isOn: $remindersSyncEnabled)
                    .disabled(DocketRuntime.isPreview)
                    .onChange(of: remindersSyncEnabled) { _, on in
                        if on { enableSync() } else { disableSync() }
                    }

                if DocketRuntime.isPreview {
                    Text("预览使用独立数据，不连接 Apple 提醒事项。").font(.caption).foregroundStyle(.secondary)
                }
                if remindersSyncEnabled {
                    if availableCalendars.isEmpty {
                        if !RemindersSync.shared.isAuthorized {
                            Text(L10n.noRemindersAccess).font(.caption).foregroundStyle(.secondary)
                            Button(restoringSyncAccess ? "正在请求授权…" : "重新授权") {
                                restoringSyncAccess = true
                                Task {
                                    defer { restoringSyncAccess = false }
                                    if await RemindersSync.shared.requestAccess() {
                                        loadSyncState()
                                        RemindersSync.shared.pullChanges(for: store.lists.filter { $0.remindersCalendarId != nil })
                                    }
                                }
                            }.disabled(restoringSyncAccess)
                            Text("恢复系统访问权限，保留已选择的同步列表。").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("当前没有可用的提醒事项列表。").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("选择要双向同步的列表；修改、达成和删除也会同步。").font(.caption).foregroundStyle(.secondary)
                            ForEach(availableCalendars, id: \.calendarIdentifier) { cal in
                                HStack(spacing: 8) {
                                    Image(systemName: syncedCalendarIds.contains(cal.calendarIdentifier) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(syncedCalendarIds.contains(cal.calendarIdentifier) ? accent : .secondary)
                                        .font(.body)
                                    Text(cal.title).font(.system(size: 12.5))
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleCalendar(cal) }
                            }
                        }

                        if let error = RemindersSync.shared.lastError {
                            Text(error).font(.caption).foregroundStyle(accent)
                        }

                        if let lastSync = RemindersSync.shared.lastSyncDate {
                            HStack(spacing: 4) {
                                Text(L10n.lastSync)
                                Text(lastSync, style: .relative)
                            }
                            .font(.caption).foregroundStyle(.tertiary)
                        }

                        Button { RemindersSync.shared.syncAll() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                                Text(L10n.syncNow).font(.caption.weight(.medium))
                            }.foregroundStyle(accent)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { loadSyncState() }
    }

    private func enableSync() {
        Task {
            let granted = await RemindersSync.shared.requestAccess()
            if granted {
                availableCalendars = RemindersSync.shared.availableCalendars()
                // Enabling access does not select or upload a user's goal set.
                syncedCalendarIds = []
                for index in store.lists.indices { store.lists[index].remindersCalendarId = nil }
                saveSyncedIds()
                store.persist()
                RemindersSync.shared.startObserving()
            } else {
                remindersSyncEnabled = false
            }
        }
    }

    private func disableSync() {
        RemindersSync.shared.stopObserving()
        syncedCalendarIds.removeAll()
        for index in store.lists.indices { store.lists[index].remindersCalendarId = nil }
        store.persist()
        saveSyncedIds()
    }

    private func toggleCalendar(_ cal: EKCalendar) {
        let id = cal.calendarIdentifier
        if syncedCalendarIds.contains(id) {
            syncedCalendarIds.remove(id)
            // Unlink from Docket list
            if let i = store.lists.firstIndex(where: { $0.remindersCalendarId == id }) {
                store.lists[i].remindersCalendarId = nil
            }
        } else {
            syncedCalendarIds.insert(id)
            linkCalendar(cal)
        }
        saveSyncedIds()
        store.persist()
        RemindersSync.shared.syncAll()
    }

    private func linkCalendar(_ cal: EKCalendar) {
        let id = cal.calendarIdentifier
        // Find or create matching Docket list
        if let i = store.lists.firstIndex(where: { $0.remindersCalendarId == id }) {
            _ = i // already linked
        } else if let i = store.lists.firstIndex(where: { $0.name == cal.title && $0.remindersCalendarId == nil }) {
            store.lists[i].remindersCalendarId = id
        } else {
            var newList = TaskList(name: cal.title, remindersCalendarId: id)
            newList.remindersCalendarId = id
            store.lists.append(newList)
        }
    }

    private func loadSyncState() {
        if remindersSyncEnabled {
            RemindersSync.shared.checkAccess()
            if RemindersSync.shared.isAuthorized {
                availableCalendars = RemindersSync.shared.availableCalendars()
                syncedCalendarIds = Set(UserDefaults.standard.stringArray(forKey: "syncedCalendarIds") ?? [])
                RemindersSync.shared.startObserving()
            }
        }
    }

    private func saveSyncedIds() {
        UserDefaults.standard.set(Array(syncedCalendarIds), forKey: "syncedCalendarIds")
    }

    // MARK: - Lists

    @State private var editingListId: UUID?
    @State private var editingName = ""
    @State private var listToDelete: TaskList?
    @State private var showDeleteConfirm = false
    @State private var hoveredListId: UUID?
    @FocusState private var listNameFocused: Bool

    private var listsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.lists).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button {
                        let existing = Set(store.lists.map(\.id))
                        store.addList(name: L10n.newList)
                        guard let added = store.lists.first(where: { !existing.contains($0.id) }) else { return }
                        editingName = added.name
                        editingListId = added.id
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(accent)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("添加目标集").accessibilityLabel("添加目标集")
                }

                VStack(spacing: 4) {
                    ForEach(store.lists) { list in
                        HStack(spacing: 10) {
                            listColorSwatch(for: list)

                            if editingListId == list.id {
                                TextField(L10n.namePlaceholder, text: $editingName)
                                    .textFieldStyle(.plain)
                                    .font(.body)
                                    .focused($listNameFocused)
                                    .onSubmit { commitListRename(list) }
                                    .onAppear {
                                        // Flicker false → true so every TextField gets a fresh
                                        // focus event, even if the previous row's edit left
                                        // `listNameFocused` set. NSTextField only runs its
                                        // select-all-on-first-responder hook on a clean focus
                                        // assignment, so without the flicker the second row's
                                        // text wouldn't be selected on auto-commit-then-switch.
                                        listNameFocused = false
                                        DispatchQueue.main.async { listNameFocused = true }
                                    }
                                Spacer()
                                Button {
                                    commitListRename(list)
                                } label: {
                                    Text(L10n.done).font(.caption.weight(.semibold)).foregroundStyle(accent)
                                        .frame(minWidth: 32, minHeight: 28).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            } else {
                                Text(list.name)
                                    .font(.body)
                                    .foregroundStyle(list.id == store.activeListId ? .primary : .secondary)
                                Spacer()
                                let showActions = hoveredListId == list.id
                                HStack(spacing: 6) {
                                    RowActionButton(systemImage: "pencil",
                                                    label: L10n.rename,
                                                    tint: accent) {
                                        beginRenamingList(list)
                                    }
                                    if !list.isDefault {
                                        RowActionButton(systemImage: "trash.fill",
                                                        label: L10n.delete,
                                                        destructive: true) {
                                            requestDeleteList(list)
                                        }
                                    }
                                }
                                .opacity(showActions ? 1 : 0)
                                .animation(.easeOut(duration: 0.12), value: showActions)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(list.id == store.activeListId ? accent.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if editingListId == nil { store.switchList(list) }
                        }
                        .onHover { isIn in
                            if isIn { hoveredListId = list.id }
                            else if hoveredListId == list.id { hoveredListId = nil }
                        }
                        .contextMenu {
                            Button(L10n.rename) { beginRenamingList(list) }
                            if !list.isDefault {
                                Button(L10n.delete, role: .destructive) { requestDeleteList(list) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - List color swatch

    /// Tappable colored square shown at the leading edge of each list row in
    /// the Lists section. Wraps the shared `ColorSwatchButton` so the popover,
    /// palette, and persistence path are identical to every other color
    /// affordance in Settings.
    @ViewBuilder
    private func listColorSwatch(for list: TaskList) -> some View {
        let isActive = list.id == store.activeListId
        ColorSwatchButton(
            hex: listColorBinding(for: list.id),
            popoverTitle: list.name,
            ringColor: isActive ? accent : nil,
            onPopoverChange: { isOpen in
                refocusListNameIfEditing(closingPopover: !isOpen, list: list)
            }
        )
    }

    /// Binding that reads/writes the chosen list's `colorHex` directly on the
    /// store (and persists). Reading from the live store rather than a captured
    /// snapshot ensures the picker always reflects the current state.
    private func listColorBinding(for listId: UUID) -> Binding<String> {
        Binding(
            get: {
                store.lists.first(where: { $0.id == listId })?.resolvedHex
                    ?? ColorPalette.defaultHex
            },
            set: { newHex in
                guard let i = store.lists.firstIndex(where: { $0.id == listId }) else { return }
                store.lists[i].colorHex = newHex
                store.persist()
            }
        )
    }

    // MARK: - List actions

    private func beginRenamingList(_ list: TaskList) {
        // Auto-commit any pending rename on a different list before switching.
        if let inFlightId = editingListId, inFlightId != list.id,
           let inFlight = store.lists.first(where: { $0.id == inFlightId }) {
            commitListRename(inFlight)
        }
        editingName = list.name
        editingListId = list.id
    }

    /// Trims whitespace from `editingName` and persists it as the list's new
    /// name. If the trimmed result is empty, falls back to the list's current
    /// name so a stray Enter or empty Done doesn't blank the row.
    private func commitListRename(_ list: TaskList) {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? list.name : trimmed
        if newName != list.name {
            store.renameList(list, to: newName)
        }
        editingListId = nil
    }

    /// Re-grabs focus on the list rename TextField after a popover (color
    /// picker) dismisses, but only if the user is still editing this row.
    /// `@FocusState` is sticky after focus is yanked away, so we briefly
    /// flicker it false → true to force a re-focus.
    private func refocusListNameIfEditing(closingPopover: Bool, list: TaskList) {
        guard closingPopover, editingListId == list.id else { return }
        listNameFocused = false
        DispatchQueue.main.async { listNameFocused = true }
    }

    /// Routes a list-delete request through the confirmation alert when the
    /// list contains tasks; deletes silently otherwise.
    private func requestDeleteList(_ list: TaskList) {
        guard !list.isDefault else { return }
        let taskCount = store.items.filter { $0.listId == list.id }.count
        if taskCount > 0 {
            listToDelete = list
            showDeleteConfirm = true
        } else {
            withAnimation { store.deleteList(list) }
        }
    }

    // MARK: - Labels Settings

    @State private var editingLabelId: UUID?
    @State private var labelName = ""
    @State private var hoveredLabelId: UUID?
    @State private var labelToDelete: TaskLabel?
    @State private var showLabelDeleteConfirm = false
    @FocusState private var labelNameFocused: Bool

    private var labelsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.labels).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button { addNewLabel() } label: {
                        Image(systemName: "plus").font(.system(size: 12.5, weight: .medium)).foregroundStyle(accent)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("添加标签").accessibilityLabel("添加标签")
                }

                if store.labelsForActiveList.isEmpty {
                    Text(L10n.noLabels).font(.caption).foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(store.labelsForActiveList) { label in
                            labelRow(label: label)
                        }
                    }
                }
            }
        }
    }

    /// Single row template that renders the label in either display or edit
    /// mode. The leading [color swatch | icon picker] cluster is identical
    /// in both — color and icon are picked through their popovers and persist
    /// immediately. The edit form therefore reduces to the name field, and
    /// the trailing affordance flips between [pencil + trash] (display) and
    /// a single [checkmark] (edit).
    private func labelRow(label: TaskLabel) -> some View {
        let isEditing = editingLabelId == label.id
        let showHover = hoveredLabelId == label.id
        let popoverTitle = isEditing
            ? (labelName.isEmpty ? L10n.newLabel : labelName)
            : label.name

        return HStack(spacing: 10) {
            ColorSwatchButton(
                hex: labelColorBinding(for: label.id),
                popoverTitle: popoverTitle,
                onPopoverChange: { isOpen in
                    refocusLabelNameIfEditing(closingPopover: !isOpen, label: label)
                }
            )
            IconPickerButton(
                icon: labelIconBinding(for: label.id),
                tint: label.color,
                popoverTitle: popoverTitle,
                onPopoverChange: { isOpen in
                    refocusLabelNameIfEditing(closingPopover: !isOpen, label: label)
                }
            )
            if isEditing {
                TextField(L10n.namePlaceholder, text: $labelName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($labelNameFocused)
                    .onSubmit { commitLabel(label) }
                    .onAppear {
                        // Flicker false → true so every TextField gets a fresh focus
                        // event. See the matching block in the list rename TextField
                        // for the rationale.
                        labelNameFocused = false
                        DispatchQueue.main.async { labelNameFocused = true }
                    }
            } else {
                Text(label.name).font(.system(size: 12.5))
            }
            Spacer()
            HStack(spacing: 6) {
                if isEditing {
                    RowActionButton(systemImage: "checkmark",
                                    label: L10n.done,
                                    tint: label.color) {
                        commitLabel(label)
                    }
                } else {
                    RowActionButton(systemImage: "pencil",
                                    label: L10n.edit,
                                    tint: label.color) {
                        beginEditingLabel(label)
                    }
                    RowActionButton(systemImage: "trash.fill",
                                    label: L10n.delete,
                                    destructive: true) {
                        requestDeleteLabel(label)
                    }
                }
            }
            .opacity(isEditing || showHover ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isEditing || showHover)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(label.color.opacity(isEditing ? 0.10 : 0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { beginEditingLabel(label) }
        }
        .onHover { isIn in
            if isIn { hoveredLabelId = label.id }
            else if hoveredLabelId == label.id { hoveredLabelId = nil }
        }
        .contextMenu {
            Button(L10n.edit) { beginEditingLabel(label) }
            Button(L10n.delete, role: .destructive) { requestDeleteLabel(label) }
        }
    }

    // MARK: - Label actions

    private func beginEditingLabel(_ label: TaskLabel) {
        // Auto-commit any pending rename on a different label before switching.
        if let inFlightId = editingLabelId, inFlightId != label.id,
           let inFlight = store.labels.first(where: { $0.id == inFlightId }) {
            commitLabel(inFlight)
        }
        labelName = label.name
        editingLabelId = label.id
    }

    /// Commits the in-progress label name to the store and exits edit mode.
    /// Color and icon are persisted live via their bindings, so the only
    /// field this commits is `name`. Trims whitespace; if the result is
    /// empty, falls back to the label's current name (so a stray Enter or
    /// empty checkmark doesn't blank the label).
    private func commitLabel(_ label: TaskLabel) {
        guard var fresh = store.labels.first(where: { $0.id == label.id }) else {
            editingLabelId = nil
            return
        }
        let trimmed = labelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? fresh.name : trimmed
        if newName != fresh.name {
            fresh.name = newName
            store.updateLabel(fresh)
        }
        editingLabelId = nil
    }

    /// Re-grabs focus on the label rename TextField after a popover (color
    /// or icon picker) dismisses, but only if the user is still editing
    /// this row.
    private func refocusLabelNameIfEditing(closingPopover: Bool, label: TaskLabel) {
        guard closingPopover, editingLabelId == label.id else { return }
        labelNameFocused = false
        DispatchQueue.main.async { labelNameFocused = true }
    }

    private func requestDeleteLabel(_ label: TaskLabel) {
        labelToDelete = label
        showLabelDeleteConfirm = true
    }

    /// Binding that reads/writes the chosen label's `colorHex` directly
    /// through the store. Mirrors `listColorBinding(for:)` so colour changes
    /// from the row swatch persist immediately, independent of the name
    /// edit form.
    private func labelColorBinding(for labelId: UUID) -> Binding<String> {
        Binding(
            get: {
                store.labels.first(where: { $0.id == labelId })?.colorHex
                    ?? ColorPalette.defaultHex
            },
            set: { newHex in
                guard var label = store.labels.first(where: { $0.id == labelId })
                else { return }
                label.colorHex = newHex
                store.updateLabel(label)
            }
        )
    }

    /// Binding that reads/writes the chosen label's `icon` directly
    /// through the store. Same shape as `labelColorBinding`.
    private func labelIconBinding(for labelId: UUID) -> Binding<String> {
        Binding(
            get: {
                store.labels.first(where: { $0.id == labelId })?.icon ?? IconPalette.defaultIcon
            },
            set: { newIcon in
                guard var label = store.labels.first(where: { $0.id == labelId })
                else { return }
                label.icon = newIcon
                store.updateLabel(label)
            }
        )
    }

    private func addNewLabel() {
        let existing = Set(store.labels.map(\.id))
        store.addLabel(name: L10n.newLabel, colorHex: ColorPalette.presets.randomElement()?.hex ?? ColorPalette.defaultHex, icon: IconPalette.defaultIcon)
        guard let newLabel = store.labelsForActiveList.first(where: { !existing.contains($0.id) }) else { return }
        labelName = newLabel.name
        editingLabelId = newLabel.id
    }

    @State private var dataFeedback: String?
    @State private var showDataFeedback = false
    @State private var showClearConfirm = false

    private var dataSection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.data).font(.system(size: 12.5, weight: .medium))
                HStack(spacing: 8) {
                    actionButton(label: L10n.exportButton, icon: "arrow.up.doc", color: accent) {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.json]
                        panel.nameFieldStringValue = "polaris-goals.json"
                        if panel.runModal() == .OK, let url = panel.url {
                            let export = DocketExport(schemaVersion: Store.currentSchemaVersion, lists: store.lists, labels: store.labels, tasks: store.items)
                            do {
                                try JSONEncoder().encode(export).write(to: url, options: .atomic)
                                reportData("已导出 \(export.tasks.count) 个目标。")
                            } catch { reportData("导出失败：\(error.localizedDescription)") }
                        }
                    }
                    actionButton(label: L10n.importButton, icon: "arrow.down.doc", color: accent) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                let plan = try GoalImportPlan(data: Data(contentsOf: url),
                                    lists: store.lists, labels: store.labels, tasks: store.items,
                                    activeListID: store.activeListId, supportedVersion: Store.currentSchemaVersion)
                                guard store.importData(lists: plan.lists, labels: plan.labels, tasks: plan.tasks) else { return }
                                reportData("已导入 \(plan.tasks.count) 个目标，跳过 \(plan.skipped) 个已有目标。")
                            } catch { reportData("未导入任何数据：\(error.localizedDescription)") }
                        }
                    }
                }
                palette.line.frame(height: 0.5)
                actionButton(
                    label: L10n.clearCompleted,
                    icon: "trash",
                    color: .red,
                    badge: "\(store.completedTasks.count)"
                ) { showClearConfirm = true }
                .disabled(store.completedTasks.isEmpty)
                .opacity(store.completedTasks.isEmpty ? 0.5 : 1)
            }
        }
    }

    private func reportData(_ message: String) {
        dataFeedback = message
        showDataFeedback = true
    }

    private func actionButton(label: String, icon: String, color: Color, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.subheadline.weight(.medium))
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(0.2)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.4), lineWidth: 1))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Matrix Settings

    @AppStorage("matrixDoFirstColor") private var doFirstColor = "#EF4444"
    @AppStorage("matrixScheduleColor") private var scheduleColor = "#3B82F6"
    @AppStorage("matrixDelegateColor") private var delegateColor = "#F59E0B"
    @AppStorage("matrixEliminateColor") private var eliminateColor = "#64748B"
    @AppStorage("matrixDoFirstLabel") private var doFirstLabel = "优先推进"
    @AppStorage("matrixScheduleLabel") private var scheduleLabel = "持续投入"
    @AppStorage("matrixDelegateLabel") private var delegateLabel = "委派协作"
    @AppStorage("matrixEliminateLabel") private var eliminateLabel = "暂时放下"
    @AppStorage("matrixLabelLength") private var matrixLabelLength = 14
    @AppStorage("matrixShowAxes") private var matrixShowAxes = true
    @AppStorage("matrixShowBadges") private var matrixShowBadges = true

    private var matrixSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.eisenhowerMatrix).font(.system(size: 12.5, weight: .medium))

                // Quadrant colors + labels
                VStack(spacing: 8) {
                    matrixQuadrantRow(label: $doFirstLabel, color: $doFirstColor, defaultLabel: "优先推进")
                    matrixQuadrantRow(label: $scheduleLabel, color: $scheduleColor, defaultLabel: "持续投入")
                    matrixQuadrantRow(label: $delegateLabel, color: $delegateColor, defaultLabel: "委派协作")
                    matrixQuadrantRow(label: $eliminateLabel, color: $eliminateColor, defaultLabel: "暂时放下")
                }

                palette.line.frame(height: 0.5)

                // Label length
                HStack {
                    Text(L10n.labelLength).font(.system(size: 12.5))
                    Spacer()
                    Text(L10n.charsCount(matrixLabelLength)).font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                }
                Slider(value: Binding(get: { Double(matrixLabelLength) }, set: { matrixLabelLength = Int($0) }), in: 6...20, step: 1)
                    .tint(accent)

                palette.line.frame(height: 0.5)

                // Toggles
                ThemedToggle(label: L10n.showAxisLabels, isOn: $matrixShowAxes)
                ThemedToggle(label: L10n.showCountBadges, isOn: $matrixShowBadges)

                palette.line.frame(height: 0.5)

                HStack {
                    Text(L10n.labelLines).font(.system(size: 12.5))
                    Spacer()
                    Picker(L10n.labelLines, selection: $matrixLineCount) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }.labelsHidden().pickerStyle(.menu).controlSize(.small)
                }
            }
        }
    }

    private func matrixQuadrantRow(label: Binding<String>, color: Binding<String>, defaultLabel: String) -> some View {
        HStack(spacing: 10) {
            ColorSwatchButton(hex: color, popoverTitle: defaultLabel)
            TextField(defaultLabel, text: label)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Visibility

    @AppStorage("showGoalInMenuBar") private var showGoalInMenuBar = true
    @AppStorage("showMatrixButton") private var showMatrixButton = true
    @AppStorage("showCompletedButton") private var showCompletedButton = true
    @AppStorage("matrixLineCount") private var matrixLineCount = 1

    private var displaySection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.display).font(.system(size: 12.5, weight: .medium))
                ThemedToggle(label: L10n.completionConfetti, isOn: $showConfetti)
                palette.line.frame(height: 0.5)
                ThemedToggle(label: "菜单栏显示主目标", isOn: $showGoalInMenuBar)
                Text("右键目标选择「显示在菜单栏」。长标题自动缩短，悬停可看全文。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var themeSection: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.theme).font(.system(size: 12.5, weight: .medium))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                    ForEach(AppTheme.allCases) { t in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { themeRaw = t.rawValue }
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    if t == .custom {
                                        Circle().fill(AngularGradient(
                                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                            center: .center
                                        ))
                                    } else {
                                        Circle().fill(t.swatchColor)
                                    }
                                }
                                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                                .overlay(
                                    Circle().stroke(Color.accentColor, lineWidth: 2.5)
                                        .opacity(t.rawValue == themeRaw ? 1 : 0)
                                )
                                .frame(width: 28, height: 28)
                                Text(t.name)
                                    .font(.system(size: 9, weight: t.rawValue == themeRaw ? .semibold : .regular))
                                    .foregroundStyle(t.rawValue == themeRaw ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if themeRaw == AppTheme.custom.rawValue {
                    customSliders
                        .padding(.top, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var customSliders: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.color).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(Color(hue: customHue, saturation: customSat, brightness: 0.95))
                    .frame(width: 16, height: 16)
            }
            Slider(value: $customHue, in: 0...1)
                .tint(Color(hue: customHue, saturation: 0.7, brightness: 0.9))
            HStack {
                Text(L10n.intensity).font(.caption).foregroundStyle(.secondary)
                Slider(value: $customSat, in: 0.05...0.6)
                    .tint(Color(hue: customHue, saturation: customSat, brightness: 0.9))
            }
        }
    }

    // MARK: - Helpers

    /// Section headings share the compact editor typography.
    @ViewBuilder
    private func groupHeader(_ text: String, first: Bool = false) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
            Spacer()
        }
        .padding(.top, first ? 0 : 12)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
