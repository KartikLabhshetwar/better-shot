import Carbon
import Foundation

@main @MainActor
enum KeyLabelCheck {
    static func main() {
        for (code, symbol, spoken) in [
            (kVK_Home, "↖", "Home"), (kVK_End, "↘", "End"),
            (kVK_PageUp, "⇞", "Page Up"), (kVK_PageDown, "⇟", "Page Down"),
            (kVK_Return, "↩", "Return"), (kVK_Escape, "⎋", "Escape"),
            (kVK_ForwardDelete, "⌦", "Forward Delete"),
            (kVK_ANSI_KeypadEnter, "⌅", "Keypad Enter"),
            (kVK_JIS_Eisu, "英数", "Eisu"), (kVK_JIS_Kana, "かな", "Kana"),
        ] {
            precondition(KeyLabel.name(for: UInt32(code)) == symbol)
            precondition(KeyLabel.accessibilityName(for: UInt32(code)) == spoken)
        }
        for (index, code) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
            kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].enumerated() {
            precondition(KeyLabel.name(for: UInt32(code)) == "F\(index + 1)")
            precondition(KeyLabel.recordingName(for: UInt32(code)) == "F\(index + 1)")
        }
        for (code, digit) in [(kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"),
            (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
            (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9")] {
            precondition(KeyLabel.name(for: UInt32(code)) == digit)
            precondition(KeyLabel.recordingName(for: UInt32(code)) == nil)
        }
        for code in [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2,
            kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6,
            kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
            kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus,
            kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEquals, kVK_JIS_KeypadComma] {
            precondition(!KeyLabel.name(for: UInt32(code)).hasPrefix("Key "))
            precondition(KeyLabel.accessibilityName(for: UInt32(code)).hasPrefix("Keypad "))
            precondition(KeyLabel.recordingName(for: UInt32(code)) == nil,
                         "Printable keypad keys must still require chord modifiers in recordings")
        }
        precondition(KeyLabel.recordingName(for: UInt32(kVK_Return)) == "⏎")
        precondition(KeyLabel.recordingName(for: UInt32(kVK_Escape)) == "esc")
        precondition(KeyLabel.recordingName(for: UInt32(kVK_Space)) == "space")
        precondition(KeyLabel.recordingName(for: UInt32(kVK_ANSI_KeypadClear)) == "clear")
        precondition(KeyLabel.name(for: UInt32.max) == "Key \(UInt32.max)")

        for (id, code, expected) in [
            ("com.apple.keylayout.US", kVK_ANSI_Y, "Y"),
            ("com.apple.keylayout.German", kVK_ANSI_Z, "Y"),
            ("com.apple.keylayout.Dvorak", kVK_ANSI_O, "R"),
            ("com.apple.keylayout.French", kVK_ANSI_Q, "A"),
        ] {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
            guard let source = sources.first, let data = KeyLabel.layoutData(for: source) else {
                preconditionFailure("Missing built-in keyboard layout \(id)")
            }
            precondition(KeyLabel.translatedName(for: UInt32(code), layoutData: data) == expected,
                         "\(id) must translate the physical key into \(expected)")
            precondition(KeyLabel.translatedName(for: UInt32.max, layoutData: data) == nil)
        }
        print("special keys, F1–F20, keypad privacy, recording style, VoiceOver, and US/German/Dvorak/French layouts")
    }
}
