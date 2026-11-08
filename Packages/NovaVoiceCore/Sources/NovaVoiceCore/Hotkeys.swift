import Foundation

/// One physical input: a key on the keyboard or a button on the mouse.
public struct HotkeyToken: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case key, mouse }

    public var kind: Kind
    public var code: Int

    public static func key(_ code: Int) -> HotkeyToken { HotkeyToken(kind: .key, code: code) }
    public static func mouse(_ button: Int) -> HotkeyToken { HotkeyToken(kind: .mouse, code: button) }

    // Mac virtual key codes for the modifier keys.
    public static let fn = key(63)
    public static let leftControl = key(59)
    public static let rightControl = key(62)
    public static let leftOption = key(58)
    public static let rightOption = key(61)
    public static let leftCommand = key(55)
    public static let rightCommand = key(54)
    public static let leftShift = key(56)
    public static let rightShift = key(60)

    /// The kind of modifier, ignoring which side of the keyboard it's on.
    private static let modifierGroups: [Int: Int] = [
        59: 0, 62: 0, 58: 1, 61: 1, 55: 2, 54: 2, 56: 3, 60: 3, 63: 4,
    ]

    public var isModifier: Bool { kind == .key && Self.modifierGroups[code] != nil }
    var modifierGroup: Int? { kind == .key ? Self.modifierGroups[code] : nil }

    /// Which modifier keys are down, from the side-specific bits macOS puts in every key event.
    public static func modifiers(rawFlags: UInt64) -> Set<HotkeyToken> {
        let bits: [(UInt64, HotkeyToken)] = [
            (0x0000_0001, leftControl), (0x0000_2000, rightControl),
            (0x0000_0020, leftOption), (0x0000_0040, rightOption),
            (0x0000_0008, leftCommand), (0x0000_0010, rightCommand),
            (0x0000_0002, leftShift), (0x0000_0004, rightShift),
            (0x0080_0000, fn),
        ]
        return Set(bits.filter { rawFlags & $0.0 != 0 }.map(\.1))
    }

    public var title: String {
        if kind == .mouse { return code == 2 ? "Middle mouse" : "Mouse \(code + 1)" }
        return Self.keyNames[code] ?? "Key \(code)"
    }

    private static let keyNames: [Int: String] = [
        63: "🌐 Fn", 59: "Left Control", 62: "Right Control", 58: "Left Option", 61: "Right Option",
        55: "Left Command", 54: "Right Command", 56: "Left Shift", 60: "Right Shift",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]
}

/// A key combination, such as Fn, Option + 1 or Mouse 4.
public struct Hotkey: Codable, Hashable, Sendable {
    public private(set) var tokens: [HotkeyToken]

    public init(_ tokens: [HotkeyToken]) {
        // Modifiers first, so "Option + 1" always reads the same however it was pressed.
        self.tokens = tokens.sorted { first, second in
            if first.isModifier != second.isModifier { return first.isModifier }
            return (first.kind.rawValue, first.code) < (second.kind.rawValue, second.code)
        }
    }

    public var title: String { tokens.map(\.title).joined(separator: " + ") }
    public var capTitles: [String] {
        // With another key in the combination either side works, so don't name a side.
        let hasOther = tokens.contains { !$0.isModifier }
        return tokens.map { token in
            guard hasOther, token.isModifier else { return token.title }
            return token.title.replacingOccurrences(of: "Left ", with: "")
                .replacingOccurrences(of: "Right ", with: "")
        }
    }

    public var isModifierOnly: Bool { tokens.allSatisfy(\.isModifier) }

    private var modifierGroups: Set<Int> { Set(tokens.compactMap(\.modifierGroup)) }
    private var others: Set<HotkeyToken> { Set(tokens.filter { !$0.isModifier }) }

    /// True when these exact inputs, and no others, are down. Used for press-to-toggle actions.
    /// With a regular key, either Option key will do. A modifier-only combination is exact.
    public func matches(pressed: Set<HotkeyToken>) -> Bool {
        let pressedOthers = pressed.filter { !$0.isModifier }
        guard others == pressedOthers, !tokens.isEmpty else { return false }
        if others.isEmpty { return Set(tokens) == pressed }
        return modifierGroups == Set(pressed.compactMap(\.modifierGroup))
    }

    /// True when at least these inputs are down. Used for hold-to-talk.
    public func isHeld(pressed: Set<HotkeyToken>) -> Bool {
        !tokens.isEmpty && Set(tokens).isSubset(of: pressed)
    }

    func conflicts(with other: Hotkey) -> Bool {
        if Set(tokens) == Set(other.tokens) { return true }
        guard !others.isEmpty else { return false }
        return others == other.others && modifierGroups == other.modifierGroups
    }

    /// The reason this combination can't be used, if there is one.
    public func problem(existing: [Hotkey]) -> HotkeyProblem? {
        if tokens.isEmpty { return .empty }
        if tokens.count > 3 { return .tooManyKeys }
        let groups = tokens.compactMap(\.modifierGroup)
        if Set(groups).count != groups.count { return .bothSides }
        if !tokens.contains(where: { $0.isModifier || $0.kind == .mouse }) { return .needsModifier }
        if existing.contains(where: conflicts(with:)) { return .alreadyInUse }
        return nil
    }

    /// Pressing this also presses the hold-to-talk key, so dictation starts first.
    public func overlaps(pushToTalk: [Hotkey]) -> Bool {
        pushToTalk.contains { $0 != self && Set($0.tokens).isSubset(of: Set(tokens)) }
    }
}

public enum HotkeyProblem: Equatable, Sendable {
    case empty, tooManyKeys, bothSides, needsModifier, alreadyInUse

    public var message: String {
        switch self {
        case .empty: "Press a key combination."
        case .tooManyKeys: "Use 3 keys or fewer."
        case .bothSides: "Use the left or the right version of a key, not both."
        case .needsModifier: "Include a modifier key such as Fn, Control or Option, or a mouse button."
        case .alreadyInUse: "That combination is already in use."
        }
    }
}

/// Everything a hotkey can do, besides running a transform.
public enum HotkeyAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case pushToTalk, handsFree, editSelection, pasteLast, scratchpad, openApp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pushToTalk: "Hold to talk"
        case .handsFree: "Hands-free"
        case .editSelection: "Edit selection"
        case .pasteLast: "Paste last dictation"
        case .scratchpad: "Open scratchpad"
        case .openApp: "Open LahLah Voice"
        }
    }

    public var detail: String {
        switch self {
        case .pushToTalk: "Hold to dictate and let go to paste. Double-tap to keep listening."
        case .handsFree: "Press to start listening and press again to stop."
        case .editSelection: "Select some text, press this, then say how to change it."
        case .pasteLast: "Puts your most recent dictation in the app in front."
        case .scratchpad: "Opens a small floating window to dictate rough notes into."
        case .openApp: "Brings up the LahLah Voice window from any app."
        }
    }

    public var defaultHotkeys: [Hotkey] {
        switch self {
        case .pushToTalk: [Hotkey([.fn])]
        case .handsFree: [Hotkey([.leftOption, .key(18)])]
        case .editSelection: [Hotkey([.leftOption, .key(19)])]
        case .pasteLast: [Hotkey([.leftOption, .key(20)])]
        case .scratchpad: [Hotkey([.leftOption, .key(21)])]
        // L for LahLah.
        case .openApp: [Hotkey([.leftOption, .key(37)])]
        }
    }
}

/// A saved instruction that rewrites selected text with Apple Intelligence.
public struct TextTransform: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var hotkey: Hotkey?

    public init(id: UUID = UUID(), name: String, prompt: String, hotkey: Hotkey? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.hotkey = hotkey
    }

    public static let starters = [
        TextTransform(name: "Fix grammar", prompt: "Fix the spelling and grammar. Keep the wording otherwise."),
        TextTransform(name: "Make it shorter", prompt: "Make this shorter and keep the meaning."),
        TextTransform(name: "More professional", prompt: "Make this sound more professional."),
    ]
}

/// Words the speaker can say that act on the text rather than being part of it.
public enum VoiceCommands {
    /// Removes a final "press enter" and reports whether it was there.
    public static func splitPressEnter(_ raw: String) -> (text: String, pressEnter: Bool) {
        let pattern = #"(?i)[\s,.;:!?-]*\b(?:press|hit)\s+(?:enter|return)\b[\s.!?]*$"#
        guard let range = raw.range(of: pattern, options: .regularExpression) else {
            return (raw, false)
        }
        return (String(raw[..<range.lowerBound]), true)
    }
}

/// Picks likely names out of the text box being written in, so they get spelled the same way.
/// Only single capitalised words are used. The rest of the text is never given to the model.
public enum ContextNames {
    public static func extract(from text: String, limit: Int = 25) -> [String] {
        var names: [String] = []
        var startOfSentence = true
        for piece in text.split(whereSeparator: \.isWhitespace) {
            let word = piece.trimmingCharacters(in: .punctuationCharacters)
            defer {
                if let last = piece.last, ".!?:".contains(last) { startOfSentence = true }
            }
            let wasStart = startOfSentence
            startOfSentence = false
            guard !wasStart, word.count >= 3, word.allSatisfy(\.isLetter),
                word.first?.isUppercase == true, !names.contains(word)
            else { continue }
            names.append(word)
        }
        return Array(names.suffix(limit))
    }
}
