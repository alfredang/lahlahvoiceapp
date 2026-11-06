import AppIntents
import Foundation

// These are compiled into both the app and the widget extension, because Control Center and the
// Live Activity need to name them. The system always runs `perform` in the app, the only process
// that can use the microphone.

struct StartVoiceSessionIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Voice Session"
    static let description = IntentDescription(
        "Opens a LahLah Voice session so you can dictate from the LahLah Voice keyboard in any app.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        #if NOVA_APP
        try await VoiceSession.shared.startSession()
        #endif
        return .result()
    }
}

struct EndVoiceSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Voice Session"
    static let description = IntentDescription("Ends the LahLah Voice session and turns the microphone off.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        #if NOVA_APP
        await VoiceSession.shared.endSession()
        #endif
        return .result()
    }
}
