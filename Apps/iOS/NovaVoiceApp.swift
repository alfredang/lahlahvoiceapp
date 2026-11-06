import AppIntents
import NovaVoiceCore
import SwiftUI

@main
struct NovaVoiceApp: App {
    @State private var session = VoiceSession.shared
    @State private var demo = DemoMode.current

    var body: some Scene {
        WindowGroup {
            MainTabView(initialTab: demo?.tab ?? .home)
                .environment(session.store)
                .environment(session)
                .tint(Brand.accent)
                .preferredColorScheme(.light)
                .onAppear { demo?.seed(session.store) }
                #if DEBUG
                .task { await DebugEvaluation.runIfRequested() }
                #endif
        }
    }
}

struct NovaVoiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceSessionIntent(),
            phrases: [
                "Start a voice session in \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start Voice Session",
            systemImageName: "mic.badge.plus")
        AppShortcut(
            intent: EndVoiceSessionIntent(),
            phrases: ["End my voice session in \(.applicationName)"],
            shortTitle: "End Voice Session",
            systemImageName: "mic.slash")
    }
}

/// Sample content for App Store screenshots, enabled only by a launch argument.
/// The sample data stays in memory and is never saved.
struct DemoMode {
    let tab: MainTabView.Tab

    static var current: DemoMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-NVDemoTab"), arguments.count > index + 1,
            let tab = MainTabView.Tab(rawValue: arguments[index + 1])
        else { return nil }
        return DemoMode(tab: tab)
    }

    static var isActive: Bool { current != nil }

    @MainActor
    func seed(_ store: NovaStore) {
        let now = Date()
        store.seedForScreenshots(
            history: [
                DictationRecord(
                    date: now.addingTimeInterval(-240),
                    raw: "um so can you uh can you send me the report by tuesday no wait wednesday morning",
                    final: "Can you send me the report by Wednesday morning?",
                    durationSeconds: 6, usedAppleIntelligence: true),
                DictationRecord(
                    date: now.addingTimeInterval(-1900),
                    raw: "hey I'm running like ten minutes late I I'll be there at three actually no quarter past three",
                    final: "Hey, I'm running ten minutes late. I'll be there at quarter past three.",
                    durationSeconds: 7, usedAppleIntelligence: true),
                DictationRecord(
                    date: now.addingTimeInterval(-5400),
                    raw: "we need three things first the budget second the timeline third the team",
                    final: "We need three things:\n1. The budget\n2. The timeline\n3. The team",
                    durationSeconds: 5, usedAppleIntelligence: true),
            ],
            notes: [
                VoiceNote(
                    date: now.addingTimeInterval(-7200), title: "Product launch planning",
                    transcript: "We talked through the launch timeline and who owns each part of it.",
                    summary: "The team agreed the launch timeline and assigned an owner to each part.\n\nAction items:\n• Share the timeline\n• Confirm owners by Friday",
                    durationSeconds: 620),
                VoiceNote(
                    date: now.addingTimeInterval(-90000), title: "Ideas for the workshop",
                    transcript: "A few ideas for making the workshop more hands-on.",
                    summary: "Ideas for making the workshop more hands-on.",
                    durationSeconds: 184),
            ],
            dictionary: [
                DictionaryEntry(term: "LahLah Voice", soundsLike: ["la la voice"]),
                DictionaryEntry(term: "Tertiary Infotech"),
                DictionaryEntry(term: "SkillsFuture", soundsLike: ["skills future"]),
            ],
            snippets: [
                Snippet(cue: "my calendar link", expansion: "https://calendar.example.com/meet"),
                Snippet(cue: "my sign off", expansion: "Thanks and best regards,\nAlex"),
            ])
    }
}

#if DEBUG
/// `-NVEval` runs the intent fixtures through the real on-device model and exits.
/// `-NVEvalFile <path>` does the same for an audio file, through the real recogniser.
enum DebugEvaluation {
    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-NVEval") }) else { return }
        // Simulator stdout redirection is unreliable, so results go to a file in Documents.
        let output = URL.documentsDirectory.appending(path: "eval.txt")
        freopen(output.path, "w", stdout)
        setbuf(stdout, nil)
        let locale = Locale(identifier: "en_US")
        if arguments.contains("-NVEval") {
            let report = await IntentEvaluation.run(locale: locale)
            print(report.text)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "-NVEvalFile"), arguments.count > index + 1 {
            do {
                let raw = try await SpeechEngine().transcribe(
                    file: URL(fileURLWithPath: arguments[index + 1]), locale: locale)
                print("HEARD:", raw)
                let result = await DictationPipeline().process(
                    raw: raw, style: .casual, locale: locale, dictionary: [], snippets: [],
                    useAppleIntelligence: true)
                print("FINAL:", result.text)
                print("AI:", result.usedAppleIntelligence)
            } catch {
                print("ERROR:", error)
            }
            exit(0)
        }
    }
}
#endif
