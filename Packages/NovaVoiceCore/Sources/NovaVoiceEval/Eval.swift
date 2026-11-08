import Foundation
import NovaVoiceCore
import NovaVoiceLocalModel

// Runs NovaVoice's real pipeline from the command line, so the editing can be measured.
//   novavoice-eval                    Run the intent fixtures through rules + Apple Intelligence.
//   novavoice-eval --file audio.aiff  Transcribe a file with SpeechAnalyzer, then run the pipeline.
//   novavoice-eval --text "…" [--style clear]  Run typed text through the pipeline in one style.
//   Add --model <Hugging Face id> to any of these to use an open model instead of Apple's.
//   With --text, add --note "…" (repeatable) to test About you notes.

@main
struct Eval {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let locale = Locale(identifier: "en_SG")

        var localModel: MLXCleanupModel?
        if let index = arguments.firstIndex(of: "--model"), arguments.count > index + 1 {
            let model = MLXCleanupModel(modelID: arguments[index + 1])
            let start = Date()
            print("Loading", model.modelID, "…")
            try await model.load { fraction in
                let percent = Int(fraction * 100)
                if percent % 10 == 0 { print("  download \(percent)%") }
            }
            print("Loaded in", String(format: "%.1fs", Date().timeIntervalSince(start)))
            localModel = model
        } else {
            print("Apple Intelligence:", AppleIntelligenceEditor.status.title)
        }
        let pipeline = DictationPipeline(localModel: localModel)
        let engine = localModel?.modelID ?? "Apple Intelligence"

        if let index = arguments.firstIndex(of: "--text"), arguments.count > index + 1 {
            let style = arguments.firstIndex(of: "--style").flatMap { i in
                arguments.count > i + 1 ? WritingStyle(rawValue: arguments[i + 1]) : nil
            } ?? .clear
            // --note "I teach group theory" (repeatable) adds an About you note.
            let notes = arguments.indices.filter { arguments[$0] == "--note" && $0 + 1 < arguments.count }
                .map { PersonalNote(text: arguments[$0 + 1]) }
            let context = PersonalContext.instructions(
                notes: notes, writingSample: "", category: .ai, style: style)
            let start = Date()
            let result = await pipeline.process(
                raw: arguments[index + 1], style: style, category: .ai, locale: locale, dictionary: [],
                snippets: [], useAppleIntelligence: true, personalContext: context)
            print("STYLE:", style.title)
            print("FINAL:", result.text)
            print("Used \(engine):", result.usedAppleIntelligence,
                  String(format: "(%.1fs)", Date().timeIntervalSince(start)))
            return
        }

        if let index = arguments.firstIndex(of: "--file"), arguments.count > index + 1 {
            let url = URL(fileURLWithPath: arguments[index + 1])
            let chosen = await SpeechEngine.bestLocale(for: locale) ?? locale
            print("Recogniser locale:", chosen.identifier)
            let raw = try await SpeechEngine().transcribe(file: url, locale: chosen)
            print("HEARD:", raw)
            let result = await pipeline.process(
                raw: raw, style: .casual, locale: chosen, dictionary: [], snippets: [],
                useAppleIntelligence: true)
            print("FINAL:", result.text)
            print("Used \(engine):", result.usedAppleIntelligence)
            return
        }

        let report = await IntentEvaluation.run(locale: locale, localModel: localModel)
        print(report.text)
        if report.passed != report.total { exit(1) }
    }
}
