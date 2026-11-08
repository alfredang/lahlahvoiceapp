import Foundation

/// Something the user wants every dictation to know, such as "I teach group theory" or "I use
/// British spelling". It can apply everywhere or only to one kind of app.
///
/// This is the useful part of what Wispr Flow calls voice preferences: short notes matched to the
/// app in front and handed to the model with each dictation. Here they never leave the Mac.
public struct PersonalNote: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    /// Nil means every app.
    public var category: AppCategory?

    public init(id: UUID = UUID(), text: String, category: AppCategory? = nil) {
        self.id = id
        self.text = text
        self.category = category
    }
}

public enum PersonalContext {
    /// Fewer words than this says too little about how someone writes.
    public static let minimumSampleWords = 40
    /// The on-device model's context is small, so only an excerpt of the sample is used.
    static let sampleExcerptLength = 700

    /// The instructions added for one dictation. Empty when there's nothing to add.
    public static func instructions(
        notes: [PersonalNote], writingSample: String, category: AppCategory?, style: WritingStyle
    ) -> String {
        var parts: [String] = []

        let matching = notes
            .filter { $0.category == nil || $0.category == category }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !matching.isEmpty {
            parts.append(
                "About the speaker. Use this only to understand and spell what they said. "
                    + "Never add any of it to the text:\n"
                    + matching.prefix(12).map { "- \($0)" }.joined(separator: "\n"))
        }

        // Exact wording and code keep the speaker's words, so a style sample would only get in the way.
        let sample = writingSample.trimmingCharacters(in: .whitespacesAndNewlines)
        if style != .verbatim, category != .code, wordCount(sample) >= minimumSampleWords {
            parts.append(
                "How the speaker writes. Match its tone, punctuation and phrasing. "
                    + "Never copy its content:\n\"\"\"\n\(excerpt(of: sample))\n\"\"\"")
        }
        return parts.joined(separator: "\n\n")
    }

    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// The start of the sample, cut at a sentence end where possible.
    static func excerpt(of sample: String) -> String {
        guard sample.count > sampleExcerptLength else { return sample }
        let cut = String(sample.prefix(sampleExcerptLength))
        if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > 200 {
            return String(cut[...end])
        }
        return cut
    }
}
