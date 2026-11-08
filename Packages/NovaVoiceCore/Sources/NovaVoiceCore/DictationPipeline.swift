import Foundation

/// App categories used to pick a writing style automatically on macOS.
public enum AppCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case messaging, ai, email, documents, code, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .messaging: "Messaging"
        case .ai: "AI assistants"
        case .email: "Email"
        case .documents: "Documents"
        case .code: "Code"
        case .other: "Everything else"
        }
    }

    public var defaultStyle: WritingStyle {
        switch self {
        case .messaging, .other: .casual
        // Prompts read best as clear questions. Code keeps exact wording for names and terms.
        case .ai: .clear
        case .code: .verbatim
        case .email, .documents: .polished
        }
    }

    public var examples: String {
        switch self {
        case .messaging: "WhatsApp, Telegram, Messages, Slack, Teams, Discord, WeChat, Signal"
        case .ai: "ChatGPT, Claude, Perplexity, Wiki LLM, Planner"
        case .email: "Mail, Outlook"
        case .documents: "Notes, Pages, Word, Notion"
        case .code: "Xcode, VS Code, Cursor, Terminal"
        case .other: "Any other app with a text field"
        }
    }
}

public enum AppCatalog {
    private static let categories: [String: AppCategory] = [
        "net.whatsapp.WhatsApp": .messaging, "desktop.WhatsApp": .messaging,
        "ru.keepcoder.Telegram": .messaging, "org.telegram.desktop": .messaging,
        "com.tdesktop.Telegram": .messaging,
        "com.apple.MobileSMS": .messaging, "com.tinyspeck.slackmacgap": .messaging,
        "com.microsoft.teams2": .messaging, "com.microsoft.teams": .messaging,
        "com.hnc.Discord": .messaging, "com.tencent.xinWeChat": .messaging,
        "org.whispersystems.signal-desktop": .messaging,
        "com.openai.chat": .ai, "com.openai.codex": .ai, "com.anthropic.claudefordesktop": .ai,
        // Wiki LLM: speech goes to its Claude Code agent, and questions are recorded verbatim.
        "com.tertiaryinfotech.markdownapp": .ai,
        // Planner: speech goes to its Hermes agent, which reads to-dos and appointments.
        "com.tertiaryinfotech.plannerapp": .ai,
        "ai.perplexity.mac": .ai, "com.apple.mail": .email, "com.microsoft.Outlook": .email,
        "com.apple.Notes": .documents, "com.apple.iWork.Pages": .documents,
        "com.microsoft.Word": .documents, "notion.id": .documents,
        "com.apple.dt.Xcode": .code, "com.microsoft.VSCode": .code,
        "com.todesktop.230313mzl4w4u92": .code, "com.apple.Terminal": .code,
        "com.googlecode.iterm2": .code, "com.exafunction.windsurf": .code,
        "com.microsoft.VSCodeInsiders": .code, "dev.zed.Zed": .code,
        "dev.warp.Warp-Stable": .code, "com.mitchellh.ghostty": .code,
        "net.kovidgoyal.kitty": .code, "io.alacritty": .code, "co.zeit.hyper": .code,
        "ai.perplexity.perplexity-mac": .ai, "im.beeper": .messaging,
    ]

    /// Web apps get the same treatment as their desktop versions.
    private static let webCategories: [(host: String, category: AppCategory)] = [
        ("chatgpt.com", .ai), ("chat.openai.com", .ai), ("claude.ai", .ai),
        ("gemini.google.com", .ai), ("perplexity.ai", .ai), ("aistudio.google.com", .ai),
        ("web.whatsapp.com", .messaging), ("web.telegram.org", .messaging),
        ("app.slack.com", .messaging), ("teams.microsoft.com", .messaging),
        ("discord.com", .messaging), ("messenger.com", .messaging),
        ("mail.google.com", .email), ("outlook.office.com", .email),
        ("outlook.live.com", .email), ("docs.google.com", .documents),
        ("notion.so", .documents), ("github.com", .code), ("replit.com", .code),
    ]

    public static func category(forHost host: String) -> AppCategory? {
        let host = host.lowercased()
        return webCategories.first { host == $0.host || host.hasSuffix("." + $0.host) }?.category
    }

    /// `host` is the page address when the app in front is a browser.
    public static func category(forBundleID bundleID: String?, host: String? = nil) -> AppCategory {
        if let host, let category = category(forHost: host) { return category }
        guard let bundleID else { return .other }
        return categories[bundleID] ?? .other
    }

    public static func style(
        forBundleID bundleID: String?, host: String? = nil, settings: NovaSettings
    ) -> WritingStyle {
        if let bundleID, let style = settings.appStyles[bundleID] { return style }
        let category = category(forBundleID: bundleID, host: host)
        return settings.categoryStyles[category.rawValue] ?? category.defaultStyle
    }
}

/// Lets a few of our own Mac apps start and stop dictation from a button of their own, the way
/// their agent panels offer a mic. They post `toggleDictation`, and LahLah Voice answers by
/// posting `state` with "listening", "working" or "idle" so the button can show it.
///
/// Distributed notifications reach any process on this Mac, so a toggle only counts while one
/// of these apps is in front: something running in the background can't start the microphone.
public enum RemoteControl {
    public static let toggleDictation = "com.tertiaryinfotech.lahlahvoice.toggleDictation"
    public static let state = "com.tertiaryinfotech.lahlahvoice.state"

    /// Wiki LLM and Planner.
    public static let allowedBundleIDs: Set<String> = [
        "com.tertiaryinfotech.markdownapp", "com.tertiaryinfotech.plannerapp",
    ]

    public static func isAllowed(_ bundleID: String?) -> Bool {
        bundleID.map(allowedBundleIDs.contains) ?? false
    }
}

/// What the speaker said, what they meant, and how the result was produced.
public struct DictationResult: Sendable {
    public let raw: String
    public let text: String
    public let usedAppleIntelligence: Bool
}

/// raw transcript → snippet check → rules → Apple Intelligence → dictionary fixes
public struct DictationPipeline: Sendable {
    private let cleaner = TranscriptCleaner()
    private let editor: AppleIntelligenceEditor

    /// With a local model, the editing step uses it instead of Apple Intelligence. With an order,
    /// the engines are tried in turn: the primary model, then the fallback.
    public init(localModel: (any LocalTextModel)? = nil, order: [CleanupEngine]? = nil) {
        editor = AppleIntelligenceEditor(localModel: localModel, order: order)
    }

    public func process(
        raw: String, style: WritingStyle, category: AppCategory? = nil, locale: Locale,
        dictionary: [DictionaryEntry], snippets: [Snippet], useAppleIntelligence: Bool,
        contextTerms: [String] = [], personalContext: String = ""
    ) async -> DictationResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DictationResult(raw: raw, text: "", usedAppleIntelligence: false)
        }

        // A snippet spoken on its own is pasted exactly as saved, never reworded.
        if let expansion = Self.wholeSnippet(in: trimmed, snippets: snippets) {
            return DictationResult(raw: raw, text: expansion, usedAppleIntelligence: false)
        }

        let ruled = cleaner.clean(trimmed, locale: locale, style: style)
        guard !ruled.isEmpty else {
            return DictationResult(raw: raw, text: "", usedAppleIntelligence: false)
        }

        // Snippets inside a sentence become placeholders so the model can't reword them.
        let (protected, placeholders) = Self.protectSnippets(in: ruled, snippets: snippets)

        var finalText = protected
        var usedAI = false
        if useAppleIntelligence, style != .verbatim || ruled != trimmed {
            let terms = dictionary.map(\.term) + contextTerms
            if let edited = await editor.edit(
                protected, style: style, category: category, locale: locale, dictionary: terms,
                personalContext: personalContext),
                placeholders.keys.allSatisfy({ edited.contains($0) })
            {
                finalText = edited
                usedAI = true
            }
        }

        finalText = Self.applyDictionary(finalText, entries: dictionary)
        for (placeholder, expansion) in placeholders {
            finalText = finalText.replacingOccurrences(of: placeholder, with: expansion)
        }
        return DictationResult(raw: raw, text: finalText, usedAppleIntelligence: usedAI)
    }

    // MARK: - Snippets

    static func wholeSnippet(in text: String, snippets: [Snippet]) -> String? {
        let spoken = normalised(text)
        return snippets.first { normalised($0.cue) == spoken && !spoken.isEmpty }?.expansion
    }

    static func protectSnippets(in text: String, snippets: [Snippet]) -> (String, [String: String]) {
        var output = text
        var placeholders: [String: String] = [:]
        // Longest cue first, so "my work email" wins over "my work".
        for (index, snippet) in snippets.sorted(by: { $0.cue.count > $1.cue.count }).enumerated() {
            let cue = snippet.cue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cue.isEmpty else { continue }
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: cue) + #"\b"#
            guard output.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            else { continue }
            let placeholder = "[[S\(index)]]"
            output = output.replacing(
                pattern, with: NSRegularExpression.escapedTemplate(for: placeholder))
            placeholders[placeholder] = snippet.expansion
        }
        return (output, placeholders)
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    // MARK: - Dictionary

    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        var output = text
        for entry in entries {
            // The term itself, with its saved capitalisation, plus anything it's misheard as.
            for spoken in [entry.term] + entry.soundsLike {
                let form = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !form.isEmpty else { continue }
                let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: form) + #"\b"#
                output = output.replacing(
                    pattern, with: NSRegularExpression.escapedTemplate(for: entry.term))
            }
        }
        return output
    }
}
