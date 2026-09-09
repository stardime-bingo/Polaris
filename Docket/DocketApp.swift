// DocketApp.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI
import AppKit
import ServiceManagement
import Carbon.HIToolbox // For kVK_* virtual key codes only

@main
enum PolarisApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // The app's only window is its existing menu-bar panel. A placeholder
        // SwiftUI Settings scene would register a second, empty native window.
        withExtendedLifetime(delegate) { application.run() }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyHandler: EventHandlerRef?
    private(set) var isRecordingShortcut = false
    private var badgeTimer: Timer?
    private var menuActivity: PolarisMenuActivity?
    private var goalObserver: NSObjectProtocol?
    private var preferencesObserver: NSObjectProtocol?
    private var verificationTrace: [[String: Any]] = []
    private var verificationNavigation: [String: Any] = [:]
    private var pendingPopoverSize: NSSize?
    private var popoverResizeScheduled = false

    var onQuickAdd: (() -> Void)?
    private var settingsRequested = false
    var onSettings: (() -> Void)? { didSet { deliverSettingsRequest() } }
    var onTipJar: (() -> Void)?
    var onPopoverClose: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        setupApplicationMenu()
        // App-scoped appearance for visual acceptance, without changing macOS settings.
        if DocketRuntime.isPreview {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--preview-appearance"), args.indices.contains(i + 1) {
                NSApp.appearance = NSAppearance(named: args[i + 1] == "light" ? .aqua : .darkAqua)
            }
        }
        NotificationManager.shared.requestPermission()

        setupPopover()
        setupStatusItem()
        if !DocketRuntime.isPreview { registerHotkey() }
        if !DocketRuntime.isPreview, UserDefaults.standard.bool(forKey: "launchAtLogin"),
           SMAppService.mainApp.status == .notRegistered {
            do { try SMAppService.mainApp.register() }
            catch { NSLog("Polaris: could not restore launch at login: %@", error.localizedDescription) }
        }
        goalObserver = NotificationCenter.default.addObserver(forName: .goalBoardChanged, object: nil, queue: .main) { [weak self] _ in self?.updateBadge() }
        preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateBadge() }

        // If the user previously enabled Reminders sync, start observing and
        // PULL current remote state so any changes made in Reminders (or via
        // Siri / Apple Watch) while Docket wasn't running surface immediately.
        //
        // We deliberately do NOT call syncAll() here: that would first push
        // every local task back to Reminders, and on launch our in-memory
        // state is by definition stale (we haven't observed remote changes
        // since the last shutdown). A push-first-then-pull ordering can
        // resurrect items the user deleted remotely, or overwrite fields the
        // user just edited on another device. Pull-only converges safely —
        // subsequent user edits will push through the normal per-mutation
        // syncPush path.
        if !DocketRuntime.isPreview, UserDefaults.standard.bool(forKey: "remindersSyncEnabled"),
           RemindersSync.shared.isAuthorized {
            RemindersSync.shared.startObserving()
            let syncedLists = Store.shared.lists.filter { $0.remindersCalendarId != nil }
            if !syncedLists.isEmpty {
                RemindersSync.shared.pullChanges(for: syncedLists)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Explicitly tear down anything that outlives the app object under
        // normal ARC rules — timers hold strong references, and event
        // monitors are owned by AppKit until removed.
        if let goalObserver { NotificationCenter.default.removeObserver(goalObserver) }
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        badgeTimer?.invalidate()
        badgeTimer = nil
        menuActivity?.stop()
        menuActivity = nil
        stopEventMonitor()
        unregisterHotkey()
        RemindersSync.shared.stopObserving()
    }

    // MARK: - Setup

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(title: "Polaris", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "Polaris")
        @discardableResult func appItem(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            applicationMenu.addItem(item)
            return item
        }
        appItem("关于 Polaris", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        applicationMenu.addItem(.separator())
        appItem("设置…", #selector(showSettings), ",", target: self)
        applicationMenu.addItem(.separator())
        let services = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        applicationMenu.addItem(servicesItem)
        NSApp.servicesMenu = services
        applicationMenu.addItem(.separator())
        appItem("隐藏 Polaris", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        appItem("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp).keyEquivalentModifierMask = [.command, .option]
        appItem("显示全部", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        applicationMenu.addItem(.separator())
        appItem("退出 Polaris", #selector(menuQuit), "q", target: self)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key, modifiers) in [
            ("撤销", "undo:", "z", NSEvent.ModifierFlags.command),
            ("重做", "redo:", "z", [.command, .shift]),
            ("剪切", "cut:", "x", .command),
            ("复制", "copy:", "c", .command),
            ("粘贴", "paste:", "v", .command),
            ("粘贴并匹配样式", "pasteAsPlainText:", "v", [.command, .option, .shift]),
            ("删除", "delete:", "", .command),
            ("全选", "selectAll:", "a", .command)
        ] {
            if title == "剪切" || title == "全选" { editMenu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            editMenu.addItem(item) // Nil target preserves the text responder chain.
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.setValue(true, forKeyPath: "shouldHideAnchor")
        let hosting = NSHostingController(rootView: ContentView())
        // The panel has one size owner. Hosting constraints must not resize its
        // native window from inside the SwiftUI layout that requests that size.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = Self.preferredPopoverSize
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(contentsOfFile: Bundle.main.path(forResource: "menubar-icon@2x", ofType: "png") ?? "")
                ?? NSImage(contentsOfFile: Bundle.main.path(forResource: "menubar-icon", ofType: "png") ?? "")
            img?.size = NSSize(width: 18, height: 18)
            img?.isTemplate = true
            button.image = img ?? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Polaris")
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            menuActivity = PolarisMenuActivity(button: button)
        }
        updateBadge()
    }

    private func setupBadgeTimer() {
        badgeTimer?.invalidate()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateBadge()
            NotificationCenter.default.post(name: .polarisClockTick, object: nil)
        }
        badgeTimer?.tolerance = 10
    }

    // MARK: - Click Handling

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.newTask, action: #selector(menuNewTask), keyEquivalent: "n"))
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let overdueCount = Store.shared.items.filter { !$0.isCompleted && $0.isOverdue }.count
        if overdueCount > 0 {
            menu.addItem(NSMenuItem(title: L10n.menuOverdue(overdueCount), action: nil, keyEquivalent: ""))
        }

        let todayCount = Store.shared.badgeCount
        menu.addItem(NSMenuItem(title: L10n.menuDueToday(todayCount), action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        #if !DOCKET_SELFBUILD
        menu.addItem(NSMenuItem(title: "☕ \(L10n.tipJar)", action: #selector(menuTipJar), keyEquivalent: ""))
        #endif
        menu.addItem(NSMenuItem(title: "GitHub", action: #selector(menuGitHub), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.menuQuit, action: #selector(menuQuit), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuNewTask() {
        if !popover.isShown { togglePopover() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.onQuickAdd?() }
    }

    @objc func showSettings() {
        guard let popover else { return }
        settingsRequested = true
        if !popover.isShown { togglePopover() }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        deliverSettingsRequest()
    }

    private func deliverSettingsRequest() {
        guard settingsRequested, let onSettings else { return }
        settingsRequested = false
        DispatchQueue.main.async(execute: onSettings)
    }

    @objc private func menuTipJar() {
        if !popover.isShown { togglePopover() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.onTipJar?() }
    }

    @objc private func menuGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/santoru/docket")!)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Badge

    func updateBadge() {
        guard let button = statusItem?.button else { return }
        let enabled = UserDefaults.standard.object(forKey: "showGoalInMenuBar") as? Bool ?? true
        let goal = enabled ? Store.shared.menuBarGoal : nil
        menuActivity?.refresh()
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = NSFont.menuBarFont(ofSize: 13)
        button.title = goal.map { GoalBoardRules.menuTitle($0.title) } ?? ""
        button.toolTip = goal.map { goal in goal.title + (goal.dueDate.map { "\n" + DueDateFormatter.format($0, hasTime: goal.hasDueTime) } ?? "") } ?? "Polaris · 目标"
        button.setAccessibilityLabel(goal.map { "主目标：" + $0.title } ?? "Polaris 目标")
        DispatchQueue.main.async { [weak self] in self?.writeRuntimeState() }
    }

    func recordVerificationEvent(_ event: String, fields: [String: Any] = [:], navigation: [String: Any]? = nil) {
        guard DocketRuntime.verificationDirectory != nil || DocketRuntime.isPreview else { return }
        if let navigation { verificationNavigation = navigation }
        verificationTrace.append(["event": event, "uptime": ProcessInfo.processInfo.systemUptime, "fields": fields, "responder": verificationResponderState()])
        if verificationTrace.count > 100 { verificationTrace.removeFirst(verificationTrace.count - 100) }
    }

    private func verificationResponderState() -> [String: Any] {
        guard let window = NSApp.keyWindow else { return [:] }
        var result: [String: Any] = ["windowNumber": window.windowNumber]
        if let responder = window.firstResponder {
            result["class"] = String(describing: type(of: responder))
            result["identity"] = String(describing: ObjectIdentifier(responder))
            if let textView = responder as? NSTextView {
                result["isFieldEditor"] = textView.isFieldEditor
                if let delegate = textView.delegate {
                    result["delegateClass"] = String(describing: type(of: delegate))
                    result["delegateIdentity"] = String(describing: ObjectIdentifier(delegate))
                }
            }
        }
        return result
    }

    /// Read back actual native UI state only in preview or explicitly requested local verification.
    func writeRuntimeState() {
        guard let dir = DocketRuntime.verificationDirectory ?? DocketRuntime.previewDirectory,
              let button = statusItem?.button else { return }
        let controller = popover?.contentViewController
        // Diagnostics must not create a hosting view earlier than normal UI use.
        let hostingView = controller?.isViewLoaded == true ? controller?.view : nil
        let panelWindow = hostingView?.window
        let state: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "panelShown": isPopoverShown,
            "refreshTimerRunning": badgeTimer?.isValid == true,
            "activityTimerRunning": menuActivity?.isAnimating == true,
            "isSyncing": RemindersSync.shared.isSyncing,
            "globalHotkeyStatus": UserDefaults.standard.integer(forKey: "globalHotkeyStatus"),
            "isRecordingShortcut": isRecordingShortcut,
            "navigation": verificationNavigation,
            "trace": verificationTrace,
            "responder": verificationResponderState(),
            "panelWindowFrame": panelWindow.map { ["x": $0.frame.minX, "y": $0.frame.minY, "width": $0.frame.width, "height": $0.frame.height] } ?? [:],
            "hostingViewFrame": hostingView.map { ["width": $0.frame.width, "height": $0.frame.height] } ?? [:],
            "windows": NSApp.windows.filter { $0.isVisible }.map { window -> [String: Any] in
                ["x": window.frame.minX, "y": window.frame.minY, "width": window.frame.width, "height": window.frame.height, "number": window.windowNumber, "key": window.isKeyWindow, "class": String(describing: type(of: window))]
            },
            "screenVisibleFrame": NSScreen.main.map { ["x": $0.visibleFrame.minX, "y": $0.visibleFrame.minY, "width": $0.visibleFrame.width, "height": $0.visibleFrame.height] } ?? [:],
            "bundleID": Bundle.main.bundleIdentifier ?? "",
            "menuTitle": button.title,
            "menuTooltip": button.toolTip ?? "",
            "menuWidth": button.bounds.width,
            "menuVisible": statusItem.isVisible,
            "panelWidth": popover.contentSize.width,
            "panelHeight": popover.contentSize.height,
            "activeGoalCount": Store.shared.items.filter { !$0.isCompleted }.count
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent("runtime-state.json"), options: .atomic)
        }
    }

    static var maximumPopoverHeight: CGFloat {
        preferredPopoverSize.height
    }

    static var preferredPopoverSize: NSSize {
        let screen = shared?.statusItem?.button?.window?.screen ?? NSScreen.main
        return GoalBoardRules.panelSize(availableHeight: screen?.visibleFrame.height ?? 800)
    }

    func resizePopover(width: CGFloat, height: CGFloat) {
        recordVerificationEvent("popover.resize.request", fields: ["width": width, "height": height])
        pendingPopoverSize = NSSize(width: width, height: height)
        guard !popoverResizeScheduled else { return }
        popoverResizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Take the latest complete request before applying. If AppKit causes
            // a new measurement, that request schedules its own following turn.
            self.popoverResizeScheduled = false
            guard let requested = self.pendingPopoverSize else { return }
            self.pendingPopoverSize = nil
            let size = NSSize(width: requested.width, height: min(Self.maximumPopoverHeight, requested.height))
            let changed = self.popover.contentSize != size
            if changed { self.popover.contentSize = size }
            self.recordVerificationEvent(changed ? "popover.resize.applied" : "popover.resize.unchanged",
                fields: ["width": size.width, "height": size.height, "requestedHeight": requested.height])
            DispatchQueue.main.async { [weak self] in self?.writeRuntimeState() }
        }
    }

    // MARK: - Global Hotkey

    func registerHotkey() {
        unregisterHotkey()
        guard !DocketRuntime.isPreview, !isRecordingShortcut else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "hotkeyEnabled") as? Bool ?? true else { defaults.set(0, forKey: "globalHotkeyStatus"); return }
        let code = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_Space
        let modifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? Int(optionKey)
        guard (0...127).contains(code), modifiers >= 0, modifiers <= Int(UInt32.max) else { defaults.set(Int(paramErr), forKey: "globalHotkeyStatus"); return }
        defaults.set(Int(installHotkey(code: UInt32(code), modifiers: UInt32(modifiers))), forKey: "globalHotkeyStatus")
    }

    func beginHotkeyRecording() { isRecordingShortcut = true; unregisterHotkey() }

    func endHotkeyRecording(restorePrevious: Bool = true) {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if restorePrevious { registerHotkey() }
    }

    /// Only commit preferences after Carbon accepts the new combination.
    func applyRecordedHotkey(code: Int, modifiers: Int, label: String) -> OSStatus {
        guard HotkeyMapping.validationError(keyCode: code, modifiers: modifiers) == nil else { return OSStatus(paramErr) }
        unregisterHotkey()
        let result = DocketRuntime.isPreview ? noErr : installHotkey(code: UInt32(code), modifiers: UInt32(modifiers))
        guard result == noErr else { return result }
        let defaults = UserDefaults.standard
        defaults.set(code, forKey: "hotkeyKeyCode")
        defaults.set(modifiers, forKey: "hotkeyModifiers")
        defaults.set(label, forKey: "hotkeyKeyLabel")
        defaults.set(true, forKey: "hotkeyEnabled")
        defaults.set(0, forKey: "globalHotkeyStatus")
        return result
    }

    private func installHotkey(code: UInt32, modifiers: UInt32) -> OSStatus {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            app.togglePopover()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotkeyHandler)
        guard handlerStatus == noErr else { return handlerStatus }
        let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x504F4C52, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotkeyRef)
        if result != noErr, let hotkeyHandler { RemoveEventHandler(hotkeyHandler); self.hotkeyHandler = nil }
        return result
    }
    private func unregisterHotkey() {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef); self.hotkeyRef = nil }
        if let hotkeyHandler { RemoveEventHandler(hotkeyHandler); self.hotkeyHandler = nil }
    }
    var isMainPanelKey: Bool { popover?.contentViewController?.view.window?.isKeyWindow == true }
    var isPopoverShown: Bool { popover?.isShown == true }

    /// SwiftUI focus proxies must resign before their navigation page is removed.
    /// Otherwise a later modifier-key event can address a deallocated focus view.
    @discardableResult func endPanelEditing() -> Bool {
        guard let window = popover?.contentViewController?.view.window else { return true }
        guard (window.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let released = window.makeFirstResponder(nil)
        recordVerificationEvent("panel.focus.released", fields: ["released": released])
        return released
    }

    // MARK: - Popover

    @objc func togglePopover() {
        recordVerificationEvent("popover.toggle", fields: ["wasShown": isPopoverShown])
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentSize = Self.preferredPopoverSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startEventMonitor()
            setupBadgeTimer()
            NotificationCenter.default.post(name: .popoverDidOpen, object: nil)
            DispatchQueue.main.async { self.writeRuntimeState() }
        }
    }

    func closePopover() {
        popover.performClose(nil)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        // Guard against double-registration — `togglePopover()` could be
        // called while the popover is still animating from a previous open,
        // and every unremoved monitor keeps firing indefinitely.
        if eventMonitor != nil { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Only close if our app lost focus (click went to another app, not a system panel like emoji picker)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if !NSApp.isActive {
                    self?.closePopover()
                }
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        recordVerificationEvent("popover.didClose")
        badgeTimer?.invalidate()
        badgeTimer = nil
        stopEventMonitor()
        updateBadge()
        onPopoverClose?()
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
    }
}

extension Notification.Name {
    static let popoverDidOpen = Notification.Name("PolarisPopoverDidOpen")
    static let polarisCommand = Notification.Name("PolarisCommand")
    static let polarisSelectGoal = Notification.Name("PolarisSelectGoal")
    static let polarisComplete = Notification.Name("PolarisComplete")
    static let polarisSave = Notification.Name("PolarisSave")
    static let polarisEscape = Notification.Name("PolarisEscape")
    static let polarisCalendarEscape = Notification.Name("PolarisCalendarEscape")
    static let polarisCancelShortcutRecording = Notification.Name("PolarisCancelShortcutRecording")
    static let polarisClockTick = Notification.Name("PolarisClockTick")
    static let popoverDidClose = Notification.Name("DocketPopoverDidClose")
    static let scrollToTipJar = Notification.Name("DocketScrollToTipJar")
}
