import Foundation

/// The deterministic editing layer. It always runs, works in every language it has rules for,
/// needs no model, and gives Apple Intelligence a cleaner starting point.
///
/// Rules favour keeping a word over deleting one the speaker meant: "I like tea" keeps "like",
/// and only filler uses such as ", like," or "so like" are removed.
public struct TranscriptCleaner: Sendable {
    public init() {}

    public func clean(_ raw: String, locale: Locale = .current, style: WritingStyle = .casual) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if Self.isEnglish(locale) {
            text = Self.applyDeletions(text)
            text = Self.removeEnglishFillers(text)
            text = Self.applyBacktracks(text)
            text = Self.removeRepeats(text)
            text = Self.applySpokenPunctuation(text)
            text = Self.formatNumberedList(text)
        } else {
            text = Self.removeCJKFillers(text, locale: locale)
            text = Self.removeRepeats(text)
        }

        text = Self.tidy(text)
        if Self.isEnglish(locale) {
            text = Self.fixCapitalisation(text)
            text = Self.addMissingEndPunctuation(text)
        }
        return Self.applyDeterministicStyle(text, style: style)
    }

    // MARK: - Language

    private static func isEnglish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "en"
    }

    // MARK: - Fillers

    private static let hardFillers =
        #"\b(?:u+h+m*|u+m+|e+r+m+|e+r+|a+h+|h+m+|m+h*m+|e+h+)\b"#

    private static func removeEnglishFillers(_ input: String) -> String {
        var text = input

        // Sounds that are never words. Also consumes the comma the recogniser puts after them.
        text = text.replacing(hardFillers + #"[,.…]*"#, with: "")

        // Filler phrases, only where they sit outside the sentence's meaning.
        let parenthetical = #"(?:like|you know|i mean|you see|sort of|kind of|basically|literally|honestly)"#
        text = text.replacing(#",\s*"# + parenthetical + #"\s*,"#, with: ",")
        text = text.replacing(
            #"(^|[.!?]\s+)(?:so\s+)?(?:like|you know|basically|well)\s*,\s*"#, with: "$1")
        text = text.replacing(#"\b(so|and|but|because)\s+like\b,?"#, with: "$1")
        text = text.replacing(#",\s*you know(?=[.!?]|$)"#, with: "")
        text = text.replacing(#"\b(?:you know\s+like|like\s+you know)\b,?"#, with: "")
        // "is like around fifty": like as a hedge in front of an estimate.
        text = text.replacing(#"\blike(?=\s+(?:around|about|maybe|roughly|almost|nearly)\b)\s*"#, with: "")

        // An opening "so" followed by a comma adds nothing.
        text = text.replacing(#"^(?:so|okay so|ok so|right so),\s+"#, with: "")
        return text
    }

    private static func removeCJKFillers(_ input: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "zh" else { return input }
        var text = input
        text = text.replacing(#"(?:^|(?<=[，。！？、\s]))(?:呃+|嗯+|额+|啊+)[，、]?"#, with: "")
        text = text.replacing(#"[，、]?(?:呃+|嗯+|额+)[，、]"#, with: "，")
        return text
    }

    // MARK: - Corrections

    /// "scratch that" and friends delete the sentence (or clause) spoken just before them.
    private static func applyDeletions(_ input: String) -> String {
        let marker = #"\b(?:scratch that|delete that|forget that|never mind that|strike that)\b[,.]?"#
        var text = input
        while let range = text.range(of: marker, options: [.regularExpression, .caseInsensitive]) {
            let before = String(text[..<range.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
            let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let kept: String
            if let boundary = before.range(
                of: #"[.!?]\s"#, options: [.regularExpression, .backwards])
            {
                kept = String(before[..<boundary.upperBound])
            } else {
                kept = ""
            }
            text = (kept + after).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// "X no wait Y": the speaker changed their mind, so Y replaces the part of X it corrects.
    private static let backtrackMarker =
        #"(?:,|\.|\s)\s*(?:no,?\s+wait|wait,?\s+no|actually,?\s+no|no,?\s+actually|no,?\s+sorry|sorry,?\s+no|oh,?\s+no,?\s+wait|sorry,?\s+i\s+mean|or\s+rather|i\s+meant|i\s+mean|make\s+that|correction|let\s+me\s+rephrase|rather|wait|actually(?=,?\s+(?:let'?s|let\s+us|make|i'?ll|we'?ll|it'?s|at|on|in)\b))[,.:?!]?\s+"#

    private static func applyBacktracks(_ input: String) -> String {
        var text = input
        var guardCount = 0
        while guardCount < 8,
            let range = text.range(
                of: backtrackMarker, options: [.regularExpression, .caseInsensitive])
        {
            guardCount += 1
            let before = String(text[..<range.lowerBound])
            let after = String(text[range.upperBound...])

            // The correction runs to the end of its sentence.
            let correctionEnd =
                after.range(of: #"[.!?](\s|$)"#, options: .regularExpression)?.lowerBound
                ?? after.endIndex
            let correction = String(after[..<correctionEnd])
            let remainder = String(after[correctionEnd...])
            guard !correction.trimmingCharacters(in: .whitespaces).isEmpty,
                !before.trimmingCharacters(in: .whitespaces).isEmpty
            else { break }

            // Only the current sentence can be corrected.
            let sentenceStart =
                before.range(of: #"[.!?]\s"#, options: [.regularExpression, .backwards])?.upperBound
                ?? before.startIndex
            let priorSentences = String(before[..<sentenceStart])
            let clause = String(before[sentenceStart...])

            let merged = merge(clause: clause, correction: correction)
            text = priorSentences + merged + remainder
        }
        return text
    }

    private static func merge(clause: String, correction: String) -> String {
        let clauseWords = clause.split(separator: " ").map(String.init)
        let correctionWords = correction.split(separator: " ").map(String.init)
        guard let first = correctionWords.first else { return clause }
        let normalise = { (word: String) in
            word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }

        // Anchor: if the correction restarts from a word already said, cut back to that word.
        // "let's go to the park, no wait, let's go to the beach" → "let's go to the beach".
        if let anchor = clauseWords.lastIndex(where: { normalise($0) == normalise(first) }),
            !connectiveWords.contains(normalise(first)) || correctionWords.count > 1
        {
            return (clauseWords[..<anchor] + correctionWords).joined(separator: " ")
        }

        // Otherwise replace the same number of trailing words, at most two.
        // "on tuesday no wait wednesday" → "on wednesday".
        var replaced = min(correctionWords.count, 2, clauseWords.count)
        // "at 3, no, 4 o'clock" corrects the time, not the "at".
        if replaced == 2,
            prepositions.contains(normalise(clauseWords[clauseWords.count - 2])),
            !prepositions.contains(normalise(first))
        {
            replaced = 1
        }
        let keep = clauseWords.dropLast(replaced)
        return (keep + correctionWords).joined(separator: " ")
    }

    private static let connectiveWords: Set<String> = ["the", "a", "an", "and", "to", "of"]
    private static let prepositions: Set<String> = [
        "at", "on", "in", "by", "to", "from", "for", "with", "before", "after", "until", "the", "a", "an",
    ]

    /// "I I think" → "I think", and "we should we should go" → "we should go".
    private static func removeRepeats(_ input: String) -> String {
        var words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return input }
        let normalise = { (word: String) in
            word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        // Doubled words that are correct English.
        let allowedDoubles: Set<String> = ["had", "that", "very", "so", "really", "bye", "no", "yes", "ha"]

        var changed = true
        while changed {
            changed = false
            var length = min(5, words.count / 2)
            while length >= 1 {
                var start = 0
                while start + 2 * length <= words.count {
                    let first = words[start..<(start + length)].map(normalise)
                    let second = words[(start + length)..<(start + 2 * length)].map(normalise)
                    let endsSentence =
                        words[start + length - 1].last.map { ".!?".contains($0) } ?? false
                    if first == second, !first.contains(""), !endsSentence,
                        !(length == 1 && allowedDoubles.contains(first[0]))
                    {
                        words.removeSubrange(start..<(start + length))
                        changed = true
                    } else {
                        start += 1
                    }
                }
                length -= 1
            }
        }
        return words.joined(separator: " ")
    }

    // MARK: - Spoken formatting

    private static func applySpokenPunctuation(_ input: String) -> String {
        var text = input
        text = text.replacing(#"[,.]?\s*\bnew paragraph\b[,.]?\s*"#, with: "\n\n")
        text = text.replacing(#"[,.]?\s*\bnew line\b[,.]?\s*"#, with: "\n")
        text = text.replacing(#"[,.]?\s*\bquestion mark\b"#, with: "?")
        text = text.replacing(#"[,.]?\s*\bexclamation (?:mark|point)\b"#, with: "!")
        text = text.replacing(#"[,.]?\s*\bfull stop\b"#, with: ".")
        text = text.replacing(#"\s+\bcomma\b(?=\s+\w)"#, with: ",")
        // "period" is also an ordinary noun, so it only counts at the very end.
        text = text.replacing(#"\s+\bperiod\b[.]?\s*$"#, with: ".")
        return text
    }

    private static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]

    /// "first buy milk second call mum third pay rent" becomes a numbered list.
    private static func formatNumberedList(_ input: String) -> String {
        guard !input.contains("\n") else { return input }

        var positions: [Range<String.Index>] = []
        var searchStart = input.startIndex
        for ordinal in ordinals {
            let pattern = #"(?:^|(?<=[\s,.:;]))"# + ordinal + #"(?:ly)?\b(?:\s+of\s+all)?[,:]?\s+"#
            guard
                let found = input.range(
                    of: pattern, options: [.regularExpression, .caseInsensitive],
                    range: searchStart..<input.endIndex)
            else { break }
            positions.append(found)
            searchStart = found.upperBound
        }
        guard positions.count >= 2 else { return input }

        var lines: [String] = []
        let intro = String(input[..<positions[0].lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
        if !intro.isEmpty { lines.append(intro + ":") }

        for (index, position) in positions.enumerated() {
            let end = index + 1 < positions.count ? positions[index + 1].lowerBound : input.endIndex
            var item = String(input[position.upperBound..<end])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:\n"))
            // A full stop between items is the recogniser's, not part of the item.
            if item.hasSuffix(".") { item.removeLast() }
            // Drop a trailing "and" that joined this item to the next one.
            if index + 1 < positions.count,
                let conjunction = item.range(
                    of: #"[,]?\s+(?:and|then|and then)$"#,
                    options: [.regularExpression, .caseInsensitive])
            {
                item.removeSubrange(conjunction)
            }
            guard let firstCharacter = item.first else { return input }
            lines.append("\(index + 1). \(firstCharacter.uppercased())\(item.dropFirst())")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tidying

    private static func tidy(_ input: String) -> String {
        var text = input
        text = text.replacing(#"[ \t]+"#, with: " ")
        text = text.replacing(#"\s+([,.!?;:])"#, with: "$1")
        text = text.replacing(#",(?:\s*,)+"#, with: ",")
        text = text.replacing(#"([.!?])\s*[,.]+"#, with: "$1")
        text = text.replacing(#",\s*([.!?])"#, with: "$1")
        text = text.replacing(#"^[\s,.;:]+"#, with: "")
        text = text.replacing(#"[ \t]*\n[ \t]*"#, with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fixCapitalisation(_ input: String) -> String {
        var text = input.replacing(#"\bi\b(?=(?:'[a-z]+)?(?:\s|[,.!?]|$))"#, with: "I", caseInsensitive: false)
        var result = ""
        var capitaliseNext = true
        for character in text {
            if capitaliseNext, character.isLetter {
                result += character.uppercased()
                capitaliseNext = false
                continue
            }
            result.append(character)
            if ".!?\n".contains(character) { capitaliseNext = true }
            // A list number such as "1." is followed by text already capitalised.
        }
        text = result
        // "may" and "march" are also everyday words, so they are left alone.
        for name in properNouns {
            let capitalised = name.prefix(1).uppercased() + name.dropFirst()
            text = text.replacing(#"\b"# + name + #"\b"#, with: capitalised)
        }
        return text
    }

    private static let properNouns = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "april", "june", "july", "august", "september", "october",
        "november", "december",
    ]

    private static let questionOpeners: Set<String> = [
        "who", "what", "when", "where", "why", "how", "which", "can", "could", "would", "should",
        "do", "does", "did", "is", "are", "was", "were", "will", "shall", "have", "has", "may",
        "am", "isn't", "aren't", "don't", "doesn't", "won't", "can't",
    ]

    private static func addMissingEndPunctuation(_ input: String) -> String {
        guard let last = input.last, last.isLetter || last.isNumber else { return input }
        // List items do not take a full stop.
        if input.contains("\n1. ") || input.hasPrefix("1. ") { return input }

        let lastLine = input.split(separator: "\n").last.map(String.init) ?? input
        let lastSentence =
            lastLine.range(of: #"[.!?]\s"#, options: [.regularExpression, .backwards])
            .map { String(lastLine[$0.upperBound...]) } ?? lastLine
        let words = lastSentence.split(separator: " ").map {
            $0.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        let opener = words.first { !["so", "and", "but", "okay", "ok", "well", "hey"].contains($0) }
        return input + (questionOpeners.contains(opener ?? "") ? "?" : ".")
    }

    private static func applyDeterministicStyle(_ input: String, style: WritingStyle) -> String {
        guard style == .veryCasual else { return input }
        var text = input
        // Keep "I" and anything the speaker clearly capitalised mid-sentence, such as names:
        // only sentence openings are lowered.
        if !text.contains("\n") {
            var result = ""
            var atStart = true
            for character in text {
                if atStart, character.isLetter {
                    result += character == "I" ? "I" : character.lowercased()
                    atStart = false
                } else {
                    result.append(character)
                    if ".!?".contains(character) { atStart = true }
                }
            }
            text = result
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}

extension String {
    /// Case-insensitive regex replacement with `$1`-style templates.
    func replacing(_ pattern: String, with template: String, caseInsensitive: Bool = true) -> String {
        let options: NSRegularExpression.Options =
            (caseInsensitive ? [.caseInsensitive] : []) + [.anchorsMatchLines]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return self
        }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }
}

extension NSRegularExpression.Options {
    fileprivate static func + (lhs: Self, rhs: Self) -> Self { lhs.union(rhs) }
}
