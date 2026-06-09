import Carbon
import Foundation

/// Renders a Carbon (keyCode, modifiers) pair as a "⌥⌘Space" style string.
/// Used by onboarding and the instant-edit settings UI.
enum KeyComboFormatter {
    static func string(keyCode: Int, modifiers: Int) -> String {
        modifierSymbols(modifiers) + keyName(keyCode)
    }

    /// Standard macOS ordering: ⌃ ⌥ ⇧ ⌘
    static func modifierSymbols(_ modifiers: Int) -> String {
        var symbols = ""
        if modifiers & controlKey != 0 { symbols += "⌃" }
        if modifiers & optionKey != 0 { symbols += "⌥" }
        if modifiers & shiftKey != 0 { symbols += "⇧" }
        if modifiers & cmdKey != 0 { symbols += "⌘" }
        return symbols
    }

    static func keyName(_ keyCode: Int) -> String {
        keyNames[keyCode] ?? "key \(keyCode)"
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]
}
