import Testing
@testable import RaccoonTools

@Suite struct KeyComboFormatterTests {

    @Test func formatsOptionCommandSpace() {
        // Default main hotkey: Space (49) + Option+Cmd (0x0900)
        #expect(KeyComboFormatter.string(keyCode: 49, modifiers: 0x0900) == "⌥⌘Space")
    }

    @Test func formatsInstantEditDefault() {
        // Default instant-edit hotkey: E (14) + Option+Cmd (0x0900)
        #expect(KeyComboFormatter.string(keyCode: 14, modifiers: 0x0900) == "⌥⌘E")
    }

    @Test func modifierOrderIsControlOptionShiftCommand() {
        // controlKey 0x1000, optionKey 0x0800, shiftKey 0x0200, cmdKey 0x0100
        #expect(KeyComboFormatter.modifierSymbols(0x1F00) == "⌃⌥⇧⌘")
        #expect(KeyComboFormatter.modifierSymbols(0x1200) == "⌃⇧")
    }

    @Test func unknownKeyCodeFallsBackToNumber() {
        #expect(KeyComboFormatter.keyName(999) == "key 999")
    }

    @Test func noModifiersYieldsBareKey() {
        #expect(KeyComboFormatter.string(keyCode: 15, modifiers: 0) == "R")
    }
}
