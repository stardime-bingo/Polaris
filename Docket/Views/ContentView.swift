import SwiftUI

@Observable final class PolarisPresentation {
    private(set) var calendarOwnerID: UUID?
    var calendarIsPresented: Bool { calendarOwnerID != nil }

    func presentCalendar(ownedBy owner: UUID) { calendarOwnerID = owner }
    func dismissCalendar(ownedBy owner: UUID? = nil) {
        if owner == nil || calendarOwnerID == owner { calendarOwnerID = nil }
    }
    var actionsArePresented = false
    var canUndoCompletion = false

    @ObservationIgnored private var pickerDismissals: [(id: UUID, dismiss: () -> Void)] = []

    func registerPicker(_ id: UUID, dismiss: @escaping () -> Void) {
        unregisterPicker(id)
        pickerDismissals.append((id, dismiss))
    }

    func unregisterPicker(_ id: UUID) {
        pickerDismissals.removeAll { $0.id == id }
    }

    @discardableResult func dismissTopPicker() -> Bool {
        guard let picker = pickerDismissals.popLast() else { return false }
        picker.dismiss()
        return true
    }

    func dismissPickers() {
        while dismissTopPicker() {}
    }
}
struct ContentView: View {
    @State private var presentation = PolarisPresentation()
    @State private var path: [NavDestination] = []
    @State private var panelHeight: CGFloat = AppDelegate.preferredPopoverSize.height
    @State private var now = Date()
    @State private var menuTracking = false
    @State private var keyMonitor: Any?
    @AppStorage("polarisSurface") private var surface = "graphite"
    @AppStorage("polarisAccent") private var accent = "klein"
    @AppStorage("panelShortcutsEnabled") private var localKeys = true
    @AppStorage("polarisMotionEnabled") private var motion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: PolarisPalette { PolarisPalette(surfaceStyle: PolarisSurface(rawValue: surface) ?? .graphite, accentStyle: PolarisAccent(rawValue: accent) ?? .klein) }
    private var editing: Bool { path.last?.isEditor == true }
    private var panelWidth: CGFloat { 408 }
    var body: some View {
      VStack(spacing: 0) {
        NavigationStack(path: $path) {
            TaskListView(path: $path)
                .opacity(path.isEmpty ? 1 : 0)
                .allowsHitTesting(path.isEmpty)
                .accessibilityHidden(!path.isEmpty)
                .navigationDestination(for: NavDestination.self) { dest in
                  Group {
                    switch dest {
                    case .create(let editorID): CreateTaskView(path: $path, editorID: editorID)
                    case .detail(let item, let editorID): TaskDetailView(item: item, path: $path, editorID: editorID)
                    case .completed: CompletedTasksView(path: $path)
                    case .settings: PolarisSettingsView(path: $path)
                    case .advancedSettings: SettingsView(path: $path)
                    case .matrix: MatrixView(path: $path)
                    }
                  }
                  .opacity(path.last == dest ? 1 : 0)
                  .allowsHitTesting(path.last == dest)
                  .accessibilityHidden(path.last != dest)
                }
        }.animation(motion && !reduceMotion ? .easeInOut(duration: 0.18) : nil, value: path)
        if !path.isEmpty {
            palette.line.frame(height: 0.5)
            PolarisFooter(onSettings: path.last == .settings ? nil : { path.append(.settings) })
        }
      }
        .frame(width: panelWidth, height: panelHeight)
        .background { PolarisPanelBackground(palette: palette) }
        .foregroundStyle(palette.ink)
        .tint(palette.accentInk)
        .environment(\.polarisPalette, palette)
        .environment(\.polarisNow, now)
        .environment(\.locale, DueDateFormatter.locale)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
        .environment(presentation)
        .alert("未能保存", isPresented: Binding(get: { Store.shared.lastPersistenceError != nil }, set: { if !$0 { Store.shared.lastPersistenceError = nil } })) {
            Button("好", role: .cancel) { Store.shared.lastPersistenceError = nil }
        } message: { Text(Store.shared.lastPersistenceError ?? "请检查磁盘空间与文件权限后重试。") }
        .onChange(of: path) { _, destination in
            // NavigationStack can retain settings without calling onDisappear.
            if destination.last != .settings {
                NotificationCenter.default.post(name: .polarisCancelShortcutRecording, object: nil)
            }
            emitVerificationState("root.navigation.changed")
        }
        .onChange(of: presentation.calendarOwnerID) { _, _ in emitVerificationState("root.calendar.changed") }
        .onChange(of: panelHeight) { _, value in
            emitVerificationState("root.height.changed")
            AppDelegate.shared?.resizePopover(width: panelWidth, height: value)
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidOpen)) { _ in now = Date(); panelHeight = AppDelegate.preferredPopoverSize.height }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in panelHeight = AppDelegate.preferredPopoverSize.height }
        .onReceive(NotificationCenter.default.publisher(for: .polarisClockTick)) { _ in now = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in menuTracking = true }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in menuTracking = false }
        .onAppear {
            emitVerificationState("root.appear")
            AppDelegate.shared?.onQuickAdd = { if path.isEmpty { path = [.create()] } }
            AppDelegate.shared?.onSettings = {
                guard path.last != .settings, path.last != .advancedSettings else { return }
                presentation.actionsArePresented = false
                presentation.dismissCalendar()
                presentation.dismissPickers()
                // Keep the editor in the stack so returning restores its draft.
                path.append(.settings)
            }
            AppDelegate.shared?.onTipJar = { path = [.advancedSettings] }
            AppDelegate.shared?.onPopoverClose = {
                presentation.dismissPickers()
                presentation.actionsArePresented = false
                presentation.dismissCalendar()
                if !path.contains(where: \.isEditor) { path = [] }
            }
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard AppDelegate.shared?.isPopoverShown == true, NSApp.isActive, NSApp.modalWindow == nil, !menuTracking else { return event }
                    if AppDelegate.shared?.isRecordingShortcut == true { return event }
                    guard AppDelegate.shared?.isMainPanelKey == true || presentation.calendarIsPresented || presentation.actionsArePresented else { return event }
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                    if event.keyCode == 53 {
                        // Pickers are above page navigation even when their native popover
                        // leaves the parent panel as the key window.
                        if presentation.dismissTopPicker() { return nil }
                        if presentation.calendarIsPresented { NotificationCenter.default.post(name: .polarisCalendarEscape, object: nil) }
                        else if presentation.actionsArePresented { presentation.actionsArePresented = false }
                        else if editing { NotificationCenter.default.post(name: .polarisEscape, object: nil) }
                        else if !path.isEmpty { path.removeLast() }
                        else { command("escape") }
                        return nil
                    }
                    guard localKeys, !presentation.calendarIsPresented else { return event }
                    let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                    let key = event.charactersIgnoringModifiers?.lowercased()
                    if path.isEmpty, mods == .command, key == "z", presentation.canUndoCompletion { command("undo"); return nil }
                    if editing, mods == .command, key == "s" { NotificationCenter.default.post(name: .polarisSave, object: nil); return nil }
                    guard path.isEmpty else { return event }
                    if mods == .command, key == "n" { path.append(.create()); return nil }
                    if mods == .command, key == "k" { command("actions"); return nil }
                    if mods == .command, key == "p" { command("pin"); return nil }
                    if mods == [.command, .shift], key == "d" { command("complete"); return nil }
                    // Preserve native text undo while the search field contains an edit.
                    if mods == .command, key == "z", ((NSApp.keyWindow?.firstResponder as? NSTextView)?.string.isEmpty ?? true) { command("undo"); return nil }
                    if mods.isEmpty {
                        if event.keyCode == 125 { command("down"); return nil }
                        if event.keyCode == 126 { command("up"); return nil }
                        if event.keyCode == 36 { command("edit"); return nil }
                    }
                    return event
                }
            }
        }
        .onDisappear {
            emitVerificationState("root.disappear")
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }
    }
    private func emitVerificationState(_ event: String) {
        guard DocketRuntime.verificationDirectory != nil || DocketRuntime.isPreview else { return }
        let routes = path.map { destination -> String in
            switch destination {
            case .create: "create"
            case .detail: "detail"
            case .settings: "settings"
            case .advancedSettings: "advancedSettings"
            case .completed: "completed"
            case .matrix: "matrix"
            }
        }
        let fields: [String: Any] = ["root": String(describing: ObjectIdentifier(presentation)), "path": routes,
            "depth": path.count, "topEditorID": path.last?.editorID?.uuidString ?? "",
            "calendarOwnerID": presentation.calendarOwnerID?.uuidString ?? "",
            "declaredWidth": panelWidth, "declaredHeight": panelHeight]
        AppDelegate.shared?.recordVerificationEvent(event, fields: fields, navigation: fields)
    }
    private func command(_ value: String) { NotificationCenter.default.post(name: .polarisCommand, object: value) }
}
private struct PolarisPickerEscapeScope: ViewModifier {
    @Binding var isPresented: Bool
    @State private var pickerID = UUID()
    @Environment(PolarisPresentation.self) private var presentation

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, shown in
                if shown {
                    let binding = $isPresented
                    presentation.registerPicker(pickerID) { binding.wrappedValue = false }
                } else {
                    presentation.unregisterPicker(pickerID)
                }
            }
            .onDisappear { presentation.unregisterPicker(pickerID) }
    }
}

extension View {
    func polarisPickerEscape(isPresented: Binding<Bool>) -> some View {
        modifier(PolarisPickerEscapeScope(isPresented: isPresented))
    }

    func polarisGlassControl() -> some View {
        self.polarisGlassSurface(capsule: true)
    }
}
