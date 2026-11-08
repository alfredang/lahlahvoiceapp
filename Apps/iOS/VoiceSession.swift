import ActivityKit
import AVFoundation
import NovaVoiceCore
import Observation
import SwiftUI

/// Holds the microphone for the keyboard. iOS keyboards can't record, so this app runs in the
/// background with an open audio session, shown by a Live Activity, and listens only when asked.
/// Between dictations the audio is thrown away, and the session closes itself when idle.
@MainActor
@Observable
final class VoiceSession {
    static let shared = VoiceSession()

    let store = NovaStore()

    private(set) var state: SessionState = .inactive
    private(set) var level: Float = 0
    private(set) var partial = ""
    private(set) var lastFailure: String?
    private(set) var sessionEndsAt: Date?

    /// Finished text when dictating inside the app rather than through the keyboard.
    var onLocalResult: ((String) -> Void)?

    private let capture = AudioCapture()
    private let speech = SpeechEngine()
    private let bridge = SessionBridge.shared
    private let cleaner = TranscriptCleaner()

    private var heartbeat: Task<Void, Never>?
    private var idleTimer: Task<Void, Never>?
    private var activity: Activity<SessionAttributes>?
    private var startedAt = Date()
    private var isLocal = false
    private var speechReady = false
    private var stopRequested = false
    private var lastLevelWrite = Date.distantPast

    private init() {
        bridge.publish(state: .inactive)

        capture.onBuffer = { [speech] in speech.append($0) }
        capture.onLevel = { [weak self] value in
            Task { @MainActor in self?.receive(level: value) }
        }
        speech.onPartial = { [weak self] text in
            Task { @MainActor in self?.partial = text }
        }

        bridge.observe(.startRequested) { [weak self] in
            Task { @MainActor in self?.beginDictation(local: false) }
        }
        bridge.observe(.stopRequested) { [weak self] in
            Task { @MainActor in self?.endDictation() }
        }
        bridge.observe(.cancelRequested) { [weak self] in
            Task { @MainActor in self?.cancelDictation() }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init) == .began
            Task { @MainActor in if began { self?.handleInterruption() } }
        }

        AppleIntelligenceEditor.prewarm()
    }

    var isOpen: Bool { state != .inactive }

    private func locale() async -> Locale {
        let requested = Locale(identifier: store.settings.localeIdentifier)
        return await SpeechEngine.bestLocale(for: requested) ?? requested
    }

    // MARK: - Session

    func startSession() async throws {
        guard !isOpen else {
            resetIdleTimer()
            return
        }
        lastFailure = nil
        guard await MicrophoneAccess.request() else {
            lastFailure = "Allow microphone access for LahLah Voice in Settings."
            throw DictationError.microphoneDenied
        }
        do {
            try await SpeechEngine.ensureInstalled(await locale())
            try capture.start()
        } catch {
            capture.stop()
            lastFailure = error.localizedDescription
            throw error
        }
        startLiveActivity()
        set(state: .ready)
        startHeartbeat()
        resetIdleTimer()
    }

    func endSession() async {
        cancelDictation()
        idleTimer?.cancel()
        heartbeat?.cancel()
        capture.stop()
        sessionEndsAt = nil
        set(state: .inactive)
        await endLiveActivity()
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [bridge] in
            while !Task.isCancelled {
                bridge.beat()
                try? await Task.sleep(for: .seconds(SessionBridge.heartbeatInterval))
            }
        }
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        let minutes = store.settings.sessionMinutes
        sessionEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
        updateLiveActivity()
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            await self?.endSession()
        }
    }

    private func handleInterruption() {
        // A phone call took the microphone. Don't pretend to still be listening.
        Task { await endSession() }
    }

    // MARK: - Dictation

    /// Dictating from inside the app works with or without an open session.
    func beginLocalDictation() async {
        if !isOpen {
            do { try await startSession() } catch { return }
        }
        beginDictation(local: true)
    }

    private func beginDictation(local: Bool) {
        guard state == .ready else { return }
        isLocal = local
        partial = ""
        speechReady = false
        stopRequested = false
        startedAt = Date()
        idleTimer?.cancel()

        speech.beginBuffering()
        capture.isForwarding = true
        set(state: .listening)

        Task {
            do {
                try await speech.start(
                    locale: await locale(), vocabulary: store.dictionary.map(\.term))
                speechReady = true
                if state != .listening {
                    await speech.cancel()
                } else if stopRequested {
                    await finish()
                }
            } catch {
                capture.isForwarding = false
                await speech.cancel()
                lastFailure = error.localizedDescription
                set(state: .ready)
                resetIdleTimer()
            }
        }
    }

    func endDictation() {
        guard state == .listening else { return }
        stopRequested = true
        guard speechReady else { return }
        Task { await finish() }
    }

    func cancelDictation() {
        guard state == .listening || state == .working else { return }
        capture.isForwarding = false
        Task { await speech.cancel() }
        set(state: .ready)
        resetIdleTimer()
    }

    private func finish() async {
        guard state == .listening else { return }
        capture.isForwarding = false
        set(state: .working)
        let duration = Date().timeIntervalSince(startedAt)
        let raw = await speech.finish()
        let chosen = await locale()

        var text = ""
        if !raw.isEmpty {
            // The keyboard's chosen style applies to its dictation, and the default applies in the app.
            let style = isLocal ? store.settings.defaultStyle : bridge.style
            // The primary model, then the fallback. Until Qwen is downloaded, Apple Intelligence
            // stands in for it.
            let settings = store.settings
            let localModel = LocalModelManager.shared.active(for: settings)
            var order = settings.engineOrder
            if localModel == nil, !order.contains(.appleIntelligence) { order.append(.appleIntelligence) }
            let pipeline = DictationPipeline(localModel: localModel, order: order)
            let result = await pipeline.process(
                raw: raw, style: style, locale: chosen, dictionary: store.dictionary,
                snippets: store.snippets, useAppleIntelligence: store.settings.useAppleIntelligence)
            text = result.text
            if !text.isEmpty {
                store.record(
                    DictationRecord(
                        raw: raw, final: text, durationSeconds: duration,
                        usedAppleIntelligence: result.usedAppleIntelligence))
            }
        }

        if isLocal {
            if !text.isEmpty { onLocalResult?(text) }
        } else if !text.isEmpty {
            bridge.publish(result: text)
        }
        partial = ""
        set(state: .ready)
        resetIdleTimer()
    }

    private func receive(level: Float) {
        self.level = level
        // Shared memory for the keyboard's waveform, written about 10 times a second at most.
        if Date().timeIntervalSince(lastLevelWrite) > 0.1 {
            lastLevelWrite = Date()
            bridge.level = level
        }
    }

    private func set(state: SessionState) {
        self.state = state
        bridge.publish(state: state)
        updateLiveActivity()
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let content = ActivityContent(state: activityState, staleDate: nil)
        activity = try? Activity.request(attributes: SessionAttributes(), content: content)
    }

    private var activityState: SessionAttributes.ContentState {
        let phase: SessionAttributes.ContentState.Phase =
            switch state {
            case .listening: .listening
            case .working: .working
            default: .ready
            }
        return SessionAttributes.ContentState(phase: phase, endsAt: sessionEndsAt ?? Date())
    }

    private func updateLiveActivity() {
        guard let activity, isOpen else { return }
        let content = ActivityContent(state: activityState, staleDate: nil)
        Task { await activity.update(content) }
    }

    private func endLiveActivity() async {
        let current = activity
        activity = nil
        await current?.end(nil, dismissalPolicy: .immediate)
    }
}

enum DictationError: LocalizedError {
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Allow microphone access for LahLah Voice in Settings."
        }
    }
}
