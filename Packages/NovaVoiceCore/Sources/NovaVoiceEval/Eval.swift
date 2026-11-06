import Foundation
import NovaVoiceCore

// Runs NovaVoice's real pipeline from the command line, so the editing can be measured.
//   novavoice-eval                    Run the intent fixtures through rules + Apple Intelligence.
//   novavoice-eval --file audio.aiff  Transcribe a file with SpeechAnalyzer, then run the pipeline.

@main
struct Eval {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let locale = Locale(identifier: "en_SG")
        let pipeline = DictationPipeline()

        print("Apple Intelligence:", AppleIntelligenceEditor.status.title)

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
            print("Used Apple Intelligence:", result.usedAppleIntelligence)
            return
        }

        let report = await IntentEvaluation.run(locale: locale)
        print(report.text)
        if report.passed != report.total { exit(1) }
    }
}
