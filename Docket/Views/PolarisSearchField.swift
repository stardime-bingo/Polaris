import SwiftUI
import AppKit

/// Native field editor preserves marked Chinese input while the list updates.
struct PolarisSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 14
    var focusGeneration: Int = 0
    var onMove: (Int) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onEscape: () -> Void = {}
    var onTab: (() -> Void)?
    var shortcutsEnabled = true
    var editorOwner: PolarisFieldEditorOwner?
    var isActive: () -> Bool = { true }
    @Environment(\.polarisPalette) private var palette
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        context.coordinator.owner.attach(field)
        field.setAccessibilityLabel(placeholder)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.owner.isActive = isActive
        let editor = field.currentEditor() as? NSTextView
        if field.stringValue != text, editor?.hasMarkedText() != true, editor?.undoManager?.isUndoing != true, editor?.undoManager?.isRedoing != true {
            // NSTextField owns its undo manager; do not alter its registration
            // state when replacing a value or switching the shared field editor.
            field.stringValue = text
        }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor:NSColor(palette.muted), .font:NSFont.systemFont(ofSize:fontSize)])
        field.textColor = NSColor(palette.ink)
        if context.coordinator.focusGeneration != focusGeneration {
            context.coordinator.focusGeneration = focusGeneration
            context.coordinator.owner.requestFocus()
        }
    }
    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.owner.detach(field)
        field.delegate = nil
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PolarisSearchField
        let owner: PolarisFieldEditorOwner
        var focusGeneration: Int?
        init(_ parent: PolarisSearchField) {
            self.parent = parent
            owner = parent.editorOwner ?? PolarisFieldEditorOwner()
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            parent.text = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            guard parent.shortcutsEnabled else { return false }
            if selector == #selector(NSResponder.insertTab(_:)), let onTab = parent.onTab { onTab(); return true }
            if selector == #selector(NSResponder.moveDown(_:)) { parent.onMove(1); return true }
            if selector == #selector(NSResponder.moveUp(_:)) { parent.onMove(-1); return true }
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            return false
        }
    }
}

/// A transient command must leave the native field editor before SwiftUI removes
/// its popover or transfers keyboard focus. Only this field's editor is released.
final class PolarisFieldEditorOwner {
    private weak var field: NSTextField?
    private var generation = 0
    var isActive: () -> Bool = { true }

    func attach(_ field: NSTextField) {
        generation &+= 1
        self.field = field
    }

    func detach(_ field: NSTextField) {
        guard self.field === field else { return }
        generation &+= 1
        self.field = nil
        isActive = { false }
    }

    func invalidate() { generation &+= 1 }

    func requestFocus() {
        generation &+= 1
        let request = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, request == self.generation, self.isActive(), NSApp.isActive,
                  let field = self.field, !field.isHiddenOrHasHiddenAncestor,
                  let window = field.window, window.isKeyWindow else { return }
            window.makeFirstResponder(field)
        }
    }

    func performAfterEndingEditing(_ action: @escaping () -> Void) {
        generation &+= 1 // Retire any focus request queued before this command.
        let request = generation
        guard let field, let window = field.window else { return }
        DispatchQueue.main.async { [weak self, weak field, weak window] in
            guard let self, request == self.generation, self.isActive(), NSApp.isActive,
                  let field, self.field === field, let window, field.window === window,
                  window.isVisible, !field.isHiddenOrHasHiddenAncestor else { return }
            if let editor = field.currentEditor() as? NSTextView {
                guard !editor.hasMarkedText(), editor.window === window,
                      window.firstResponder === editor else { return }
            }
            // The calendar grid can own a SwiftUI KeyViewProxy even after the
            // text field has ended editing. Retire that responder too, while
            // this popover's view hierarchy is still alive.
            guard window.makeFirstResponder(nil) else { return }
            guard request == self.generation, self.isActive(), field.currentEditor() == nil else { return }
            AppDelegate.shared?.recordVerificationEvent("nativeField.command.released", fields: [
                "windowNumber": window.windowNumber,
                "field": String(describing: ObjectIdentifier(field)),
                "stillEditing": field.currentEditor() != nil
            ])
            action()
        }
    }
}
