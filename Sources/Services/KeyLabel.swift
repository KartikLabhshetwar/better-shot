import Carbon
import Foundation

/// Shortcut and recording-overlay key labels, translated through the current keyboard layout.
@MainActor
enum KeyLabel {
    private static let specialKeys: [UInt32: (symbol: String, spoken: String)] = [
        36: ("↩", "Return"), 48: ("⇥", "Tab"), 49: ("Space", "Space"),
        51: ("⌫", "Delete"), 53: ("⎋", "Escape"), 71: ("⌧", "Clear"),
        76: ("⌅", "Keypad Enter"), 115: ("↖", "Home"), 116: ("⇞", "Page Up"),
        117: ("⌦", "Forward Delete"), 119: ("↘", "End"), 121: ("⇟", "Page Down"),
        123: ("←", "Left Arrow"), 124: ("→", "Right Arrow"),
        125: ("↓", "Down Arrow"), 126: ("↑", "Up Arrow"),
        102: ("英数", "Eisu"), 104: ("かな", "Kana"),
    ]
    private static let functionKeys: [UInt32] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]
    private static let digits: [UInt32: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]
    private static let keypad: [UInt32: String] = [
        65: ".", 67: "*", 69: "+", 75: "/", 78: "−", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
        87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 95: ",",
    ]
    private static let fallback: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
        0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0A: "§", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
        0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K", 0x2C: "/",
        0x2D: "N", 0x2E: "M", 0x18: "=", 0x1B: "−", 0x27: "'",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2F: ".", 0x32: "`",
        0x5D: "¥", 0x5E: "_",
    ]

    static func name(for code: UInt32) -> String {
        if let special = specialKey(for: code) {
            return special.symbol
        }
        if let digit = digits[code] {
            return digit
        }
        if let key = keypad[code] {
            return key
        }
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = layoutData(for: source), let translated = translatedName(for: code, layoutData: data) {
            return translated
        }
        return fallback[code] ?? "Key \(code)"
    }

    static func accessibilityName(for code: UInt32) -> String {
        if let special = specialKey(for: code) {
            return special.spoken
        }
        if let key = keypad[code] {
            let spoken = [".": "Decimal", "*": "Multiply", "+": "Plus", "/": "Divide",
                "−": "Minus", "=": "Equals", ",": "Comma"][key] ?? key
            return "Keypad \(spoken)"
        }
        return name(for: code)
    }

    /// The recording overlay's label for a special key; nil for keys that type text, which recordings must not capture alone.
    static func recordingName(for code: UInt32) -> String? {
        guard let special = specialKey(for: code) else { return nil }
        switch code {
        case 36: return "⏎"
        case 49: return "space"
        case 53: return "esc"
        case 71: return "clear"
        default: return special.symbol
        }
    }

    private static func specialKey(for code: UInt32) -> (symbol: String, spoken: String)? {
        if let index = functionKeys.firstIndex(of: code) {
            let name = "F\(index + 1)"
            return (name, name)
        }
        return specialKeys[code]
    }

    static func layoutData(for source: TISInputSource) -> CFData? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
    }

    static func translatedName(for code: UInt32, layoutData: CFData) -> String? {
        guard code <= UInt16.max, CFDataGetLength(layoutData) >= MemoryLayout<UCKeyboardLayout>.size,
              let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length).uppercased()
        guard name.rangeOfCharacter(from: .controlCharacters.union(.whitespacesAndNewlines)) == nil else { return nil }
        return name
    }
}
