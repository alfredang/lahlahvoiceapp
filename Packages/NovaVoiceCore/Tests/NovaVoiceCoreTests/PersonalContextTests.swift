import Foundation
import Testing

@testable import NovaVoiceCore

struct PersonalContextTests {
    private let notes = [
        PersonalNote(text: "I teach group theory and representation theory."),
        PersonalNote(text: "Sign off emails with Best, Alfred.", category: .email),
    ]
    private let sample = Array(repeating: "I keep my messages short and friendly.", count: 8)
        .joined(separator: " ")

    @Test func notesForEveryAppAndTheAppInFront() {
        let ai = PersonalContext.instructions(notes: notes, writingSample: "", category: .ai, style: .clear)
        #expect(ai.contains("group theory"))
        #expect(!ai.contains("Best, Alfred"))
        let email = PersonalContext.instructions(notes: notes, writingSample: "", category: .email, style: .polished)
        #expect(email.contains("Best, Alfred"))
    }

    @Test func nothingToAddIsEmpty() {
        #expect(PersonalContext.instructions(notes: [], writingSample: "Too short.", category: .ai, style: .clear).isEmpty)
    }

    @Test func writingSampleIsSkippedForExactWordingAndCode() {
        #expect(PersonalContext.instructions(notes: [], writingSample: sample, category: .messaging, style: .casual)
            .contains("How the speaker writes"))
        #expect(PersonalContext.instructions(notes: [], writingSample: sample, category: .messaging, style: .verbatim).isEmpty)
        #expect(PersonalContext.instructions(notes: [], writingSample: sample, category: .code, style: .casual).isEmpty)
    }

    @Test func longSamplesAreCutAtASentence() {
        let long = Array(repeating: "This is one sentence of my writing.", count: 60).joined(separator: " ")
        let excerpt = PersonalContext.excerpt(of: long)
        #expect(excerpt.count <= 700)
        #expect(excerpt.hasSuffix("."))
    }
}

struct ModelReplyTests {
    @Test func labelsQuotesAndThinkingAreStripped() {
        #expect(AppleIntelligenceEditor.plainReply("<think>\nhmm\n</think>\n\nText: \"Send it Friday.\"") == "Send it Friday.")
        #expect(AppleIntelligenceEditor.plainReply("Cleaned transcript: Hello there.") == "Hello there.")
    }

    @Test func aRecitedDictionaryIsRemoved() {
        let reply = "Ask Priya about the D3 slides.\nPriya, D3, LahLah Voice"
        #expect(AppleIntelligenceEditor.withoutRecitedDictionary(reply, ["Priya", "D3", "LahLah Voice"])
            == "Ask Priya about the D3 slides.")
    }

    @Test func aDoubledReplyIsRejected() {
        let said = "can you send the report to the finance team by friday afternoon please"
        let once = "Can you send the report to the finance team by Friday afternoon, please?"
        #expect(AppleIntelligenceEditor.isFaithful(once, to: said, style: .casual))
        #expect(!AppleIntelligenceEditor.isFaithful(once + " " + once, to: said, style: .casual))
    }
}
