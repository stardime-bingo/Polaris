// HotkeyMapping.swift
// Docket — pure helpers for the global hotkey.

import AppKit
import Carbon.HIToolbox

/// Pure conversions between Carbon modifier masks (the legacy representation the
/// app persists in `UserDefaults`) and Cocoa `NSEvent.ModifierFlags` (what the
/// runtime event monitors compare against). Kept free of any app state so it can
/// be unit-tested in isolation.
enum HotkeyMapping {
    static func displayString(keyCode: Int, modifiers: Int, recordedLabel: String? = nil) -> String {
        var parts = ""
        if modifiers & controlKey != 0 { parts += "⌃" }
        if modifiers & optionKey != 0 { parts += "⌥" }
        if modifiers & shiftKey != 0 { parts += "⇧" }
        if modifiers & cmdKey != 0 { parts += "⌘" }
        return parts + " " + keyLabel(keyCode: keyCode, characters: recordedLabel)
    }

    static func keyLabel(keyCode: Int, characters: String? = nil) -> String {
        let special = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "Esc",
                       kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
                       kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤"]
        if let label = special[keyCode] { return label }
        let functionKeys = [kVK_F1,kVK_F2,kVK_F3,kVK_F4,kVK_F5,kVK_F6,kVK_F7,kVK_F8,kVK_F9,kVK_F10,kVK_F11,kVK_F12,kVK_F13,kVK_F14,kVK_F15,kVK_F16,kVK_F17,kVK_F18,kVK_F19,kVK_F20]
        if let index = functionKeys.firstIndex(of: keyCode) { return "F\(index + 1)" }
        if let characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
            return characters.uppercased()
        }
        let ansi = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`"]
        return ansi[keyCode] ?? "Key \(keyCode)"
    }

    static func carbonModifiers(fromCocoa flags: NSEvent.ModifierFlags) -> Int {
        var value = 0
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.shift) { value |= shiftKey }
        if flags.contains(.command) { value |= cmdKey }
        return value
    }

    static func validationError(keyCode: Int, modifiers: Int) -> String? {
        guard (0...127).contains(keyCode) else { return "这个按键无法用作全局快捷键。" }
        guard modifiers & (cmdKey | controlKey | optionKey) != 0 else { return "请同时按住 ⌘、⌃ 或 ⌥，避免影响正常输入。" }
        let reserved: [(Int, Int)] = [(kVK_Space, cmdKey), (kVK_Space, controlKey), (kVK_Space, cmdKey | optionKey),
                                      (kVK_Tab, cmdKey), (kVK_Tab, cmdKey | shiftKey), (kVK_Escape, cmdKey | optionKey),
                                      (kVK_ANSI_Q, cmdKey | controlKey), (kVK_ANSI_3, cmdKey | shiftKey),
                                      (kVK_ANSI_4, cmdKey | shiftKey), (kVK_ANSI_5, cmdKey | shiftKey)]
        if reserved.contains(where: { $0.0 == keyCode && $0.1 == modifiers }) { return "这个组合由 macOS 使用，请换一个组合。" }
        return nil
    }

    /// Convert a Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`,
    /// `controlKey`, OR-combined) into `NSEvent.ModifierFlags`.
    static func cocoaModifiers(fromCarbon carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var mods: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey) != 0 { mods.insert(.command) }
        if carbonMods & UInt32(shiftKey) != 0 { mods.insert(.shift) }
        if carbonMods & UInt32(optionKey) != 0 { mods.insert(.option) }
        if carbonMods & UInt32(controlKey) != 0 { mods.insert(.control) }
        return mods
    }
}
