import Foundation
import Testing

@testable import NovaVoiceCore

@Suite struct HotkeyTests {
    private let optionOne = Hotkey([.leftOption, .key(18)])

    @Test func chordsAcceptEitherSideOfAModifier() {
        #expect(optionOne.matches(pressed: [.leftOption, .key(18)]))
        #expect(optionOne.matches(pressed: [.rightOption, .key(18)]))
        #expect(!optionOne.matches(pressed: [.leftOption, .leftShift, .key(18)]))
        #expect(!optionOne.matches(pressed: [.leftOption]))
    }

    @Test func modifierOnlyCombinationsAreExact() {
        let hotkey = Hotkey([.rightOption])
        #expect(hotkey.matches(pressed: [.rightOption]))
        #expect(!hotkey.matches(pressed: [.leftOption]))
        #expect(!hotkey.matches(pressed: [.rightOption, .leftShift]))
    }

    @Test func holdIsStillHeldWithExtraKeysDown() {
        #expect(Hotkey([.fn]).isHeld(pressed: [.fn, .key(49)]))
        #expect(!Hotkey([.fn]).isHeld(pressed: [.key(49)]))
    }

    @Test func rejectsInvalidCombinations() {
        #expect(Hotkey([]).problem(existing: []) == .empty)
        #expect(Hotkey([.fn, .leftOption, .leftShift, .key(1)]).problem(existing: []) == .tooManyKeys)
        #expect(Hotkey([.leftOption, .rightOption]).problem(existing: []) == .bothSides)
        #expect(Hotkey([.key(0)]).problem(existing: []) == .needsModifier)
        #expect(Hotkey([.rightOption, .key(18)]).problem(existing: [optionOne]) == .alreadyInUse)
    }

    @Test func acceptsValidCombinations() {
        #expect(Hotkey([.fn]).problem(existing: []) == nil)
        #expect(Hotkey([.mouse(3)]).problem(existing: []) == nil)
        #expect(Hotkey([.leftControl, .key(49)]).problem(existing: [optionOne]) == nil)
    }

    @Test func notesOverlapWithHoldToTalk() {
        #expect(Hotkey([.fn, .key(49)]).overlaps(pushToTalk: [Hotkey([.fn])]))
        #expect(!optionOne.overlaps(pushToTalk: [Hotkey([.fn])]))
    }

    @Test func readsModifiersFromEventFlags() {
        #expect(HotkeyToken.modifiers(rawFlags: 0x0080_0000) == [.fn])
        #expect(HotkeyToken.modifiers(rawFlags: 0x40) == [.rightOption])
        #expect(HotkeyToken.modifiers(rawFlags: 0x21) == [.leftOption, .leftControl])
    }

    @Test func oldSettingsFilesStillLoadAndKeepTheChosenKey() throws {
        let old = #"{"localeIdentifier":"en_SG","useAppleIntelligence":false,"keepHistory":true,"defaultStyle":"casual","categoryStyles":{},"appStyles":{},"pushToTalkKey":"rightOption","sessionMinutes":9,"hasCompletedOnboarding":true}"#
        let settings = try JSONDecoder().decode(NovaSettings.self, from: Data(old.utf8))
        #expect(settings.localeIdentifier == "en_SG")
        #expect(settings.useAppleIntelligence == false)
        #expect(settings.sessionMinutes == 9)
        #expect(settings.hotkeys(for: .pushToTalk) == [Hotkey([.rightOption])])
        #expect(settings.hotkeys(for: .handsFree) == HotkeyAction.handsFree.defaultHotkeys)
        #expect(settings.transforms.count == TextTransform.starters.count)
    }

    @Test func pressEnterCommandOnlyMatchesAtTheEnd() {
        #expect(VoiceCommands.splitPressEnter("see you soon, press enter.") == ("see you soon", true))
        #expect(VoiceCommands.splitPressEnter("Press Enter") == ("", true))
        #expect(VoiceCommands.splitPressEnter("press enter to continue").pressEnter == false)
    }

    @Test func contextNamesSkipSentenceStarts() {
        let names = ContextNames.extract(from: "Thanks for that. Please ask Priya and Mr Tan about Tertiary. We met.")
        #expect(names == ["Priya", "Tan", "Tertiary"])
    }
}
