import Foundation

/// Learns words from the user's own corrections, so they're recognised next time.
///
/// After a paste, the text box is read again a little later. If the user replaced a word in what
/// was pasted ("turns and flicks" → "turns and flips"), the word they typed is returned so it can
/// go in the dictionary. Dictionary words are given to the recogniser as vocabulary, which makes
/// it more likely to hear them.
///
/// Only the corrected word is learned, never a rule that rewrites the misheard one. A deliberate
/// edit, such as changing Tuesday to Friday, then can't change what later dictations say.
public enum CorrectionLearner {
    /// Words the user typed in place of what was heard, in the order they appear.
    /// `fieldText` is everything in the text box, which may hold more than the paste.
    /// Returns nothing if the pasted text can't be found there with confidence.
    public static func learnedWords(pasted: String, fieldText: String, known: [String] = []) -> [String] {
        let original = words(in: pasted)
        let field = words(in: fieldText)
        guard original.count >= 2, !field.isEmpty else { return [] }
        guard let edited = bestMatch(for: original, in: field) else { return [] }

        let knownWords = Set(known.map { $0.lowercased() })
        var learned: [String] = []
        for (heard, typed) in substitutions(original, edited) {
            let key = typed.lowercased()
            guard key != heard.lowercased(), isLearnable(typed), !knownWords.contains(key),
                !learned.contains(where: { $0.lowercased() == key })
            else { continue }
            learned.append(typed)
        }
        return learned
    }

    // MARK: - Finding the edited passage

    /// The run of field words that lines up best with the pasted words, if most of them still match.
    static func bestMatch(for original: [String], in field: [String]) -> [String]? {
        let n = original.count
        var best: (words: [String], matches: Int)?
        // The edited passage can be a few words longer or shorter than the paste.
        for length in max(1, n - 3)...(n + 3) where length <= field.count {
            for start in 0...(field.count - length) {
                let window = Array(field[start..<(start + length)])
                let matches = alignment(original, window).filter { $0.op == .match }.count
                if matches > (best?.matches ?? 0) { best = (window, matches) }
            }
        }
        // Mostly the same words, but not identical: that's an edit of this paste.
        guard let best, Double(best.matches) / Double(n) >= 0.6, best.matches < n || best.words.count != n
        else { return nil }
        return best.words
    }

    // MARK: - Word alignment

    enum Op { case match, substitute, insert, delete }

    /// Single words swapped for single words, with unchanged words (or the ends) on both sides.
    static func substitutions(_ a: [String], _ b: [String]) -> [(heard: String, typed: String)] {
        let steps = alignment(a, b)
        var result: [(String, String)] = []
        for (index, step) in steps.enumerated() where step.op == .substitute {
            let before = index == 0 || steps[index - 1].op == .match
            let after = index == steps.count - 1 || steps[index + 1].op == .match
            if before, after, let i = step.a, let j = step.b { result.append((a[i], b[j])) }
        }
        return result
    }

    /// Levenshtein alignment over words, compared without case.
    static func alignment(_ a: [String], _ b: [String]) -> [(op: Op, a: Int?, b: Int?)] {
        let x = a.map { $0.lowercased() }, y = b.map { $0.lowercased() }
        var cost = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { cost[i][0] = i }
        for j in 0...y.count { cost[0][j] = j }
        for i in stride(from: 1, through: x.count, by: 1) {
            for j in stride(from: 1, through: y.count, by: 1) {
                let swap = cost[i - 1][j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
                cost[i][j] = min(swap, cost[i - 1][j] + 1, cost[i][j - 1] + 1)
            }
        }
        var steps: [(Op, Int?, Int?)] = []
        var i = x.count, j = y.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1) {
                steps.append((x[i - 1] == y[j - 1] ? .match : .substitute, i - 1, j - 1))
                i -= 1
                j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                steps.append((.delete, i - 1, nil))
                i -= 1
            } else {
                steps.append((.insert, nil, j - 1))
                j -= 1
            }
        }
        return steps.reversed()
    }

    // MARK: - Words

    /// Splits on spaces and drops punctuation at either end, keeping words like "D3" and "don't".
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    /// Worth learning: has a letter, isn't a common word, and isn't one CJK run (no word breaks).
    static func isLearnable(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 40, word.contains(where: \.isLetter) else { return false }
        if word.unicodeScalars.contains(where: { (0x3040...0x9FFF).contains($0.value) }) { return false }
        return !stopwords.contains(word.lowercased())
    }

    static let stopwords: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are",
        "as", "at", "be", "because", "been", "before", "being", "below", "between", "both", "but",
        "by", "can", "could", "did", "do", "does", "doing", "done", "down", "during", "each", "few",
        "for", "from", "further", "get", "got", "had", "has", "have", "having", "he", "her", "here",
        "hers", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "it's", "just",
        "know", "like", "me", "more", "most", "my", "no", "nor", "not", "now", "of", "off", "ok",
        "okay", "on", "once", "one", "only", "or", "other", "our", "out", "over", "own", "right",
        "same", "say", "see", "she", "should", "so", "some", "such", "than", "that", "the", "their",
        "them", "then", "there", "these", "they", "this", "those", "through", "to", "too", "two",
        "under", "until", "up", "us", "very", "was", "way", "we", "well", "were", "what", "when",
        "where", "which", "while", "who", "whom", "why", "will", "with", "would", "yes", "yeah",
        "you", "your", "yours", "i'm", "don't", "can't", "won't", "let", "make", "want", "need",
        "think", "thing", "things", "also", "really", "much", "many", "new", "good", "time",
    ]
}
