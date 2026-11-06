import Foundation
import Observation

/// Keeps settings, dictionary, snippets, history and notes in local JSON files.
/// Nothing here is ever sent off the device.
@MainActor
@Observable
public final class NovaStore {
    public static let appGroup = "group.com.tertiaryinfotech.novavoice"
    public static let historyLimit = 1000

    public var settings = NovaSettings() { didSet { save(settings, to: "settings") } }
    public var dictionary: [DictionaryEntry] = [] { didSet { save(dictionary, to: "dictionary") } }
    public var snippets: [Snippet] = [] { didSet { save(snippets, to: "snippets") } }
    public private(set) var history: [DictationRecord] = []
    public var notes: [VoiceNote] = [] { didSet { save(notes, to: "notes") } }

    private let directory: URL
    private var loading = true

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
        settings = load("settings") ?? NovaSettings()
        dictionary = load("dictionary") ?? []
        snippets = load("snippets") ?? []
        history = load("history") ?? []
        notes = load("notes") ?? []
        loading = false
    }

    public static func defaultDirectory() -> URL {
        // Only iOS shares data with a keyboard. On macOS, asking for a group container the app
        // isn't entitled to creates one anyway and can trigger a privacy prompt.
        #if os(iOS)
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup)
        {
            return group.appending(path: "NovaVoice", directoryHint: .isDirectory)
        }
        #endif
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "NovaVoice", directoryHint: .isDirectory)
    }

    // MARK: - History

    public func record(_ record: DictationRecord) {
        guard settings.keepHistory else { return }
        history.insert(record, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        save(history, to: "history")
    }

    public func deleteHistory(_ record: DictationRecord) {
        history.removeAll { $0.id == record.id }
        save(history, to: "history")
    }

    public func clearHistory() {
        history = []
        save(history, to: "history")
    }

    /// Replaces in-memory state for the on-screen demo used by App Store screenshots.
    public func seedForScreenshots(
        history: [DictationRecord], notes: [VoiceNote], dictionary: [DictionaryEntry],
        snippets: [Snippet]
    ) {
        loading = true
        self.history = history
        self.notes = notes
        self.dictionary = dictionary
        self.snippets = snippets
        loading = false
    }

    // MARK: - Stats

    public struct Stats: Sendable {
        public let totalWords: Int
        public let dictations: Int
        public let wordsPerMinute: Int
        public let minutesSaved: Int
    }

    public var stats: Stats {
        let words = history.reduce(0) { $0 + $1.wordCount }
        let seconds = history.reduce(0) { $0 + $1.durationSeconds }
        let wpm = seconds > 0 ? Int(Double(words) / (seconds / 60)) : 0
        // Compared with typing at an average 40 words per minute.
        let saved = max(Int(Double(words) / 40 - seconds / 60), 0)
        return Stats(
            totalWords: words, dictations: history.count, wordsPerMinute: wpm, minutesSaved: saved)
    }

    // MARK: - Files

    private func url(for name: String) -> URL { directory.appending(path: "\(name).json") }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard !loading, let data = try? JSONEncoder().encode(value) else { return }
        #if os(iOS)
        // .completeUntilFirstUserAuthentication keeps files readable while a session runs
        // with the phone locked, and still encrypted before the first unlock.
        try? data.write(
            to: url(for: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url(for: name), options: .atomic)
        #endif
    }
}
