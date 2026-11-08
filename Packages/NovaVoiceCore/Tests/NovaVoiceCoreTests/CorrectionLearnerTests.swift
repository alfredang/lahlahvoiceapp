import Testing

@testable import NovaVoiceCore

struct CorrectionLearnerTests {
    private let pasted = "You show the example of the turns and the flicks, right? Are they the D3 group?"

    @Test func learnsTheWordTheUserTypedInstead() {
        let field = "You show the example of the turns and the flips, right? Are they the D3 group?"
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: field) == ["flips"])
    }

    @Test func findsThePasteInsideLongerText() {
        let field = "Earlier message.\nYou show the example of the turns and the flips, right? Are they the S3 group?\n> "
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: field) == ["flips", "S3"])
    }

    @Test func nothingWhenUnchanged() {
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: "Hi. " + pasted).isEmpty)
    }

    @Test func nothingWhenThePasteIsGone() {
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: "Something else entirely").isEmpty)
    }

    @Test func ignoresCommonWordsCaseAndPunctuation() {
        let field = "you show an example of the turns and the flicks right. Are they the D3 group"
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: field).isEmpty)
    }

    @Test func skipsWordsAlreadyInTheDictionary() {
        let field = "You show the example of the turns and the flips, right? Are they the D3 group?"
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: field, known: ["Flips"]).isEmpty)
    }

    @Test func rewrittenPhrasesAreNotLearned() {
        // Several neighbouring words changed: a rewrite, not a mis-hearing.
        let field = "You show the example of rotations and reflections, right? Are they the D3 group?"
        #expect(CorrectionLearner.learnedWords(pasted: pasted, fieldText: field).isEmpty)
    }
}

struct ClearStyleTests {
    /// A real dictation: thinking aloud about group representations.
    private let spoken = """
        Okay, I think I roughly understand. So the, for D3, there are 3 partition, the identity, the 2 rotation \
        and three reflection, and the time, the dimension of the partition, which is the number elements inside \
        there, you add up to the order of the group, it makes sense, one +2 +3, go to 6. Right? And this is \
        straightforward, is just follow the partition. And then you say that the, each partition, Kind of \
        correspond to one irreput, irreputable representation, right? So there are 3 partitions, so there are 3 \
        irreducible representation. And it turns out that for, 2 of them are, dimensional one, there's only one \
        element. And the other one is a dimension two. Representation. So it's one square plus 2 square that give \
        you 6. And So discount or explain the, how you add up, but how is trays come into here? Is there any, how \
        the trace related to the irreducible representation? How does it be useful? I don't understand at all.
        """

    private let clearRewrite = """
        I think I roughly understand. For D3 there are 3 classes: the identity, the 2 rotations and the 3 \
        reflections. Their sizes add up to the order of the group: 1 + 2 + 3 = 6. Each class corresponds to one \
        irreducible representation, so there are 3 irreducible representations. Two of them are one-dimensional \
        and one is two-dimensional, so 1² + 1² + 2² = 6. That explains how the counts add up, but where does the \
        trace come in? How is the trace related to the irreducible representations, and how is it useful? I \
        don't understand that at all.
        """

    @Test func clearRewriteOfARambleIsAccepted() {
        #expect(AppleIntelligenceEditor.isFaithful(clearRewrite, to: spoken, style: .clear))
    }

    @Test func spokenNumbersMayBecomeDigitsButNoneMayBeInvented() {
        let input = "it's one plus two plus three which gives six"
        #expect(AppleIntelligenceEditor.isFaithful("It's 1 + 2 + 3, which gives 6.", to: input, style: .verbatim))
        #expect(!AppleIntelligenceEditor.isFaithful("It's 1 + 2 + 3, which gives 7.", to: input, style: .verbatim))
    }

    @Test func aClearRewriteMustNotAnswerTheQuestion() {
        let answered = "The trace of each matrix gives the character, which identifies the irreducible representation."
        #expect(!AppleIntelligenceEditor.isFaithful(answered, to: spoken, style: .clear))
    }

    @Test func aiAppsDefaultToClear() {
        #expect(AppCategory.ai.defaultStyle == .clear)
        #expect(AppCategory.code.defaultStyle == .verbatim)
    }
}
