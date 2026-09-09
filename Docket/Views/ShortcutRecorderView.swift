import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A window-scoped event monitor exists only while the user is recording.
struct ShortcutRecorderView: View {
    @AppStorage("hotkeyEnabled") private var enabled = true
    @AppStorage("hotkeyKeyCode") private var keyCode = kVK_Space
    @AppStorage("hotkeyModifiers") private var modifiers = Int(optionKey)
    @AppStorage("hotkeyKeyLabel") private var recordedLabel = ""
    @AppStorage("globalHotkeyStatus") private var registrationStatus = 0
    @State private var recording = false
    @State private var monitor: Any?
    @State private var windowNumber: Int?
    @State private var heldModifiers = ""
    @State private var error: String?
    @State private var hovered = false
    @State private var hitRegion = ShortcutRecorderHitRegion()
    @FocusState private var recorderFocused: Bool
    @Environment(\.polarisPalette) private var palette
    private var shortcut: String {
        enabled ? HotkeyMapping.displayString(keyCode: keyCode, modifiers: modifiers, recordedLabel: recordedLabel.isEmpty ? nil : recordedLabel) : "点按录制"
    }
    private var hint: String {
        if let error { return error }
        if recording { return "按下组合键 · Esc 取消 · Delete 清除" }
        if enabled, registrationStatus != 0 { return "快捷键未能注册，请点按重新录制。" }
        return "点按右侧录制，在任何应用中打开或收起 Polaris。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("全局唤醒").font(.system(size: 12.5))
                Spacer()
                Button { recording ? stop() : start() } label: {
                    Text(recording ? (heldModifiers.isEmpty ? "请按快捷键…" : heldModifiers + " …") : shortcut)
                        .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        .frame(minWidth: 142, minHeight: 26)
                        .foregroundStyle(recording ? palette.accentInk : palette.ink)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                        .background { ShortcutRecorderHitArea(region: hitRegion) }
                }.buttonStyle(ShortcutRecorderButtonStyle(recording: recording, hovered: hovered, focused: recorderFocused))
                    .focused($recorderFocused).onHover { hovered = $0 }
                    .accessibilityLabel(recording ? "取消快捷键录制" : "录制全局快捷键").accessibilityValue(shortcut)
                Button(action: clear) {
                    Image(systemName: "xmark").font(.system(size: 11)).frame(width: 28, height: 32).contentShape(Rectangle())
                }.buttonStyle(GoalControlStyle()).foregroundStyle(palette.muted).disabled(!enabled && !recording)
                    .help("清除快捷键").accessibilityLabel("清除全局快捷键")
            }
            Text(hint).font(.system(size: 11)).foregroundStyle(error == nil ? palette.secondary : palette.accentInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: .polarisCancelShortcutRecording)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.windowNumber == windowNumber { stop() }
        }
    }

    private func start() {
        guard !recording, let window = NSApp.keyWindow, let app = AppDelegate.shared else { return }
        window.makeFirstResponder(nil)
        windowNumber = window.windowNumber
        error = nil; heldModifiers = ""; recording = true
        app.beginHotkeyRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { event in
            guard recording, NSApp.isActive else { return event }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if !hitRegion.contains(event) { stop() }
                return event
            }
            guard NSApp.keyWindow?.windowNumber == windowNumber else { return event }
            let mask = HotkeyMapping.carbonModifiers(fromCocoa: event.modifierFlags)
            if event.type == .flagsChanged {
                heldModifiers = HotkeyMapping.displayString(keyCode: kVK_Space, modifiers: mask).replacingOccurrences(of: " Space", with: "")
                return nil
            }
            guard !event.isARepeat else { return nil }
            let code = Int(event.keyCode)
            if mask == 0, code == kVK_Escape { stop(); return nil }
            if mask == 0, code == kVK_Delete || code == kVK_ForwardDelete { clear(); return nil }
            if mask == 0, code == kVK_Tab { stop(); window.selectNextKeyView(nil); return nil }
            if let message = HotkeyMapping.validationError(keyCode: code, modifiers: mask) { error = message; return nil }
            let label = HotkeyMapping.keyLabel(keyCode: code, characters: event.charactersIgnoringModifiers)
            let result = app.applyRecordedHotkey(code: code, modifiers: mask, label: label)
            if result == noErr { error = nil; stop(restorePrevious: false) }
            else { error = "这个组合已被占用或无法注册，请换一个。原快捷键尚未更改。" }
            return nil
        }
        if monitor == nil { stop(); error = "暂时无法录制，请再试一次。" }
    }
    private func stop(restorePrevious: Bool = true) {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard recording else { return }
        recording = false; heldModifiers = ""; windowNumber = nil; error = nil
        AppDelegate.shared?.endHotkeyRecording(restorePrevious: restorePrevious)
    }
    private func clear() {
        stop(restorePrevious: false)
        enabled = false; error = nil
        AppDelegate.shared?.registerHotkey()
    }
}

/// Reads the native button bounds without participating in hit testing.
private final class ShortcutRecorderHitRegion {
    weak var view: NSView?
    func contains(_ event: NSEvent) -> Bool {
        guard let view, !view.isHiddenOrHasHiddenAncestor,
              let window = view.window, event.windowNumber == window.windowNumber else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }
}

private struct ShortcutRecorderHitArea: NSViewRepresentable {
    let region: ShortcutRecorderHitRegion
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        view.setAccessibilityElement(false)
        region.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct ShortcutRecorderButtonStyle: ButtonStyle {
    let recording: Bool
    let hovered: Bool
    let focused: Bool
    @Environment(\.polarisPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(configuration.isPressed ? palette.pressed : recording ? palette.selection : hovered ? palette.hover : palette.raised)
                .padding(.vertical, 3))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(recording || focused ? palette.accentInk : palette.line, lineWidth: recording || focused ? 2 : 0.5)
                .padding(.vertical, 3))
    }
}
