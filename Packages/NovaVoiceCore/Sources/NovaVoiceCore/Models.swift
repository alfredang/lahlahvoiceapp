import Foundation
@_exported import NovaVoiceBridge

/// A word or name the speech engine should favour, with an optional spoken form to replace.
public struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var term: String
    /// Mis-hearings to rewrite to `term`, for example "nova voice" → "LahLah Voice".
    public var soundsLike: [String]

    public init(id: UUID = UUID(), term: String, soundsLike: [String] = []) {
        self.id = id
        self.term = term
        self.soundsLike = soundsLike
    }
}

/// A spoken cue that expands to saved text, for example "my calendar link".
public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var cue: String
    public var expansion: String

    public init(id: UUID = UUID(), cue: String, expansion: String) {
        self.id = id
        self.cue = cue
        self.expansion = expansion
    }
}

/// One finished dictation, kept on this device only.
public struct DictationRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var raw: String
    public var final: String
    public var appName: String?
    public var durationSeconds: Double
    public var usedAppleIntelligence: Bool

    public init(
        id: UUID = UUID(), date: Date = Date(), raw: String, final: String, appName: String? = nil,
        durationSeconds: Double, usedAppleIntelligence: Bool
    ) {
        self.id = id
        self.date = date
        self.raw = raw
        self.final = final
        self.appName = appName
        self.durationSeconds = durationSeconds
        self.usedAppleIntelligence = usedAppleIntelligence
    }

    public var wordCount: Int { final.split(whereSeparator: \.isWhitespace).count }
}

/// A longer voice note with a transcript and an optional Apple Intelligence summary.
public struct VoiceNote: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var transcript: String
    public var summary: String?
    /// The transcript tidied into what was meant, when Apple Intelligence could do it.
    public var cleaned: String?
    public var durationSeconds: Double

    public init(
        id: UUID = UUID(), date: Date = Date(), title: String, transcript: String,
        summary: String? = nil, cleaned: String? = nil, durationSeconds: Double
    ) {
        self.cleaned = cleaned
        self.id = id
        self.date = date
        self.title = title
        self.transcript = transcript
        self.summary = summary
        self.durationSeconds = durationSeconds
    }
}

public struct NovaSettings: Codable, Equatable, Sendable {
    /// The engines to try for each dictation, in order: the primary model, then the fallback.
    public var engineOrder: [CleanupEngine] {
        var order = [cleanupEngine]
        if let fallbackEngine, fallbackEngine != cleanupEngine { order.append(fallbackEngine) }
        return order
    }

    /// True when the open model is the primary or the fallback, so it should be downloaded.
    public var usesLocalModel: Bool { engineOrder.contains(.localModel) }

    public var localeIdentifier: String
    public var useAppleIntelligence: Bool
    /// Apple Intelligence by default. An open model is opt-in and downloaded on first use.
    public var cleanupEngine: CleanupEngine
    public var localModelID: String
    /// Tried when the primary model is unavailable, declines or gives an unfaithful edit. Nil:
    /// no fallback (the rule-based text is kept). Only one open model is used at a time, so the
    /// fallback is always the other kind of engine.
    public var fallbackEngine: CleanupEngine?
    /// About you: notes every dictation should know, and a sample of how you write.
    public var personalNotes: [PersonalNote]
    public var writingSample: String
    public var keepHistory: Bool
    public var defaultStyle: WritingStyle
    /// Style per app category on macOS. Missing categories use the catalog default.
    public var categoryStyles: [String: WritingStyle]
    /// Style per app bundle identifier on macOS. Takes priority over category styles.
    public var appStyles: [String: WritingStyle]
    /// The hold-to-talk choice from before custom hotkeys. Used only to carry that choice over.
    public var pushToTalkKey: PushToTalkKey
    /// iOS only: minutes a session stays open while idle.
    public var sessionMinutes: Int
    public var hasCompletedOnboarding: Bool

    // macOS only.
    /// Combinations per `HotkeyAction`. A missing action uses its default.
    public var customHotkeys: [String: [Hotkey]]
    public var transforms: [TextTransform]
    public var scratchpad: String
    public var playSounds: Bool
    public var muteWhileDictating: Bool
    /// Off by default, because pressing Return sends the message in most chat apps.
    public var pressEnterCommand: Bool
    /// Reads names from the focused text box to spell them correctly. Stays on this Mac.
    public var useTextBoxContext: Bool
    /// Wiki LLM and Planner: press Return after pasting, so the agent answers straight away.
    public var sendInAgentApps: Bool
    /// While listening hands-free, Space finishes and sends, like a chat app's voice message.
    public var spaceToSend: Bool
    /// Learns a word when you correct how it was heard, so it's written right next time. Reads
    /// the text box again after a paste, on this Mac only, so it's off until turned on.
    public var learnCorrections: Bool

    public init(
        localeIdentifier: String = Locale.current.identifier,
        useAppleIntelligence: Bool = true,
        cleanupEngine: CleanupEngine = .appleIntelligence,
        localModelID: String = LocalModelOption.defaultID,
        fallbackEngine: CleanupEngine? = nil,
        personalNotes: [PersonalNote] = [],
        writingSample: String = "",
        keepHistory: Bool = true,
        defaultStyle: WritingStyle = .casual,
        categoryStyles: [String: WritingStyle] = [:],
        appStyles: [String: WritingStyle] = [:],
        pushToTalkKey: PushToTalkKey = .fn,
        sessionMinutes: Int = 5,
        hasCompletedOnboarding: Bool = false,
        customHotkeys: [String: [Hotkey]] = [:],
        transforms: [TextTransform] = TextTransform.starters,
        scratchpad: String = "",
        playSounds: Bool = true,
        muteWhileDictating: Bool = false,
        pressEnterCommand: Bool = false,
        useTextBoxContext: Bool = false,
        sendInAgentApps: Bool = true,
        spaceToSend: Bool = true,
        learnCorrections: Bool = false
    ) {
        self.localeIdentifier = localeIdentifier
        self.useAppleIntelligence = useAppleIntelligence
        self.cleanupEngine = cleanupEngine
        self.localModelID = localModelID
        self.fallbackEngine = fallbackEngine
        self.personalNotes = personalNotes
        self.writingSample = writingSample
        self.keepHistory = keepHistory
        self.defaultStyle = defaultStyle
        self.categoryStyles = categoryStyles
        self.appStyles = appStyles
        self.pushToTalkKey = pushToTalkKey
        self.sessionMinutes = sessionMinutes
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.customHotkeys = customHotkeys
        self.transforms = transforms
        self.scratchpad = scratchpad
        self.playSounds = playSounds
        self.muteWhileDictating = muteWhileDictating
        self.pressEnterCommand = pressEnterCommand
        self.useTextBoxContext = useTextBoxContext
        self.sendInAgentApps = sendInAgentApps
        self.spaceToSend = spaceToSend
        self.learnCorrections = learnCorrections
    }

    /// Reads settings saved by any earlier version. Anything missing takes its default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = NovaSettings()
        localeIdentifier = try values.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? base.localeIdentifier
        useAppleIntelligence = try values.decodeIfPresent(Bool.self, forKey: .useAppleIntelligence) ?? base.useAppleIntelligence
        cleanupEngine = try values.decodeIfPresent(CleanupEngine.self, forKey: .cleanupEngine) ?? base.cleanupEngine
        localModelID = try values.decodeIfPresent(String.self, forKey: .localModelID) ?? base.localModelID
        fallbackEngine = try values.decodeIfPresent(CleanupEngine.self, forKey: .fallbackEngine)
        personalNotes = try values.decodeIfPresent([PersonalNote].self, forKey: .personalNotes) ?? []
        writingSample = try values.decodeIfPresent(String.self, forKey: .writingSample) ?? ""
        keepHistory = try values.decodeIfPresent(Bool.self, forKey: .keepHistory) ?? base.keepHistory
        defaultStyle = try values.decodeIfPresent(WritingStyle.self, forKey: .defaultStyle) ?? base.defaultStyle
        categoryStyles = try values.decodeIfPresent([String: WritingStyle].self, forKey: .categoryStyles) ?? [:]
        appStyles = try values.decodeIfPresent([String: WritingStyle].self, forKey: .appStyles) ?? [:]
        pushToTalkKey = try values.decodeIfPresent(PushToTalkKey.self, forKey: .pushToTalkKey) ?? .fn
        sessionMinutes = try values.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? base.sessionMinutes
        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        customHotkeys = try values.decodeIfPresent([String: [Hotkey]].self, forKey: .customHotkeys) ?? [:]
        transforms = try values.decodeIfPresent([TextTransform].self, forKey: .transforms) ?? base.transforms
        scratchpad = try values.decodeIfPresent(String.self, forKey: .scratchpad) ?? ""
        playSounds = try values.decodeIfPresent(Bool.self, forKey: .playSounds) ?? base.playSounds
        muteWhileDictating = try values.decodeIfPresent(Bool.self, forKey: .muteWhileDictating) ?? false
        pressEnterCommand = try values.decodeIfPresent(Bool.self, forKey: .pressEnterCommand) ?? false
        useTextBoxContext = try values.decodeIfPresent(Bool.self, forKey: .useTextBoxContext) ?? false
        sendInAgentApps = try values.decodeIfPresent(Bool.self, forKey: .sendInAgentApps) ?? base.sendInAgentApps
        spaceToSend = try values.decodeIfPresent(Bool.self, forKey: .spaceToSend) ?? base.spaceToSend
        learnCorrections = try values.decodeIfPresent(Bool.self, forKey: .learnCorrections) ?? base.learnCorrections
    }

    public func hotkeys(for action: HotkeyAction) -> [Hotkey] {
        if let saved = customHotkeys[action.rawValue] { return saved }
        return action == .pushToTalk ? [Hotkey([pushToTalkKey.token])] : action.defaultHotkeys
    }

    public mutating func setHotkeys(_ hotkeys: [Hotkey], for action: HotkeyAction) {
        customHotkeys[action.rawValue] = hotkeys
    }

    /// Every combination in use except the one being changed, so duplicates can be refused.
    public func hotkeysInUse(excluding action: HotkeyAction? = nil, transform: UUID? = nil) -> [Hotkey] {
        let fixed = HotkeyAction.allCases.filter { $0 != action }.flatMap { hotkeys(for: $0) }
        return fixed + transforms.filter { $0.id != transform }.compactMap(\.hotkey)
    }

    /// How to describe the main dictation key in instructions.
    public var holdToTalkTitle: String {
        hotkeys(for: .pushToTalk).first?.capTitles.joined(separator: " + ") ?? "your hotkey"
    }
}

public enum PushToTalkKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case fn, rightOption, rightCommand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fn: "Fn (Globe)"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        }
    }

    var token: HotkeyToken {
        switch self {
        case .fn: .fn
        case .rightOption: .rightOption
        case .rightCommand: .rightCommand
        }
    }
}
