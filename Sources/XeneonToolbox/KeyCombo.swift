import AppKit
import Carbon.HIToolbox

/// Posting and describing keyboard shortcuts for Hotkey deck tiles — Stream
/// Deck's most-used action, sent system-wide to whatever app is frontmost.
enum KeyCombo {
    /// Fire the combo as a synthetic key press (needs the Accessibility grant
    /// the touch driver already has).
    static func post(keyCode: CGKeyCode, modifiers: UInt) {
        // NSEvent.ModifierFlags and CGEventFlags share bit positions for the
        // device-independent modifiers, so the raw value carries over.
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(20_000)
        up?.post(tap: .cghidEventTap)
        AppLog.info("deck", "posted hotkey code=\(keyCode) flags=\(modifiers)")
    }

    /// "⌘⇧4"-style description of a captured combo.
    static func display(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyName(keyCode)
    }

    /// Human name for a virtual key code — letters/digits via the current
    /// keyboard layout, special keys from a fixed table.
    static func keyName(_ keyCode: Int) -> String {
        switch keyCode {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: break
        }
        // Translate through the current layout so "4" is "4" and "a" is "A".
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        var deadKeys: UInt32 = 0
        let status = data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> OSStatus in
            let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "key \(keyCode)" }
        let name = String(utf16CodeUnits: chars, count: length).uppercased()
        // Function/media keys translate to invisible private-use glyphs.
        let printable = name.unicodeScalars.allSatisfy { $0.value >= 0x20 && !(0xF700...0xF8FF).contains($0.value) }
        return printable && !name.trimmingCharacters(in: .whitespaces).isEmpty ? name : "key \(keyCode)"
    }
}
