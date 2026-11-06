import AppKit
import NovaVoiceCore
import Observation

/// Runs a dictation from key press to pasted text, in whichever app is in front.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case listening(handsFree: Bool, command: Bool)
        case working
    }

    private(set) var phase: Phase = .idle
    private(set) var level: Float = 0
    private(set) var partial = ""
    private(set) var lastMessage: String?
    private(set) var accessibilityGranted = TextInserter.isTrusted

    private let store: NovaStore
    private let capture = AudioCapture()
    private let speech = SpeechEngine()
    private let pipeline = DictationPipeline()
    private let hotkeys = HotkeyMonitor()
    private let hud = HUDController()
    private let scratchpad: ScratchpadController

    private var startedAt = Date()
    private var targetApp: NSRunningApplication?
    /// The website in front, when the target app is a browser.
    private var targetHost: String?
    private var commandSelection: String?
    /// Names read from the text box being written in, when that setting is on.
    private var contextTerms: [String] = []
    /// Set when the user releases the key before the recogniser finished starting.
    private var stopRequested = false
    private var startTask: Task<Void, Never>?
    private var speechReady = false

    init(store: NovaStore) {
        self.store = store
        scratchpad = ScratchpadController(store: store)
    }

    var isActive: Bool { phase != .idle }

    var menuBarSymbol: String {
        switch phase {
        case .idle: "waveform"
        case .listening: "mic.fill"
        case .working: "ellipsis"
        }
    }

    var statusLine: String {
        switch phase {
        case .idle: "Hold \(store.settings.holdToTalkTitle) to dictate"
        case .listening(_, let command): command ? "Listening for your edit…" : "Listening…"
        case .working: "Writing…"
        }
    }

    func activate() {
        capture.onBuffer = { [speech] in speech.append($0) }
        capture.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        speech.onPartial = { [weak self] text in
            Task { @MainActor in self?.partial = text }
        }
        hud.bind(to: self)

        hotkeys.onPushToTalkDown = { [weak self] in self?.beginDictation(handsFree: false) }
        hotkeys.onPushToTalkUp = { [weak self] in self?.endDictation() }
        hotkeys.onLockHandsFree = { [weak self] in self?.lockHandsFree() }
        hotkeys.onTrigger = { [weak self] in self?.handle($0) }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        hotkeys.isDictationActive = { [weak self] in self?.isActive ?? false }

        startHotkeys()
        AppleIntelligenceEditor.prewarm()

        Task {
            let locale = await currentLocale()
            try? await SpeechEngine.ensureInstalled(locale)
        }
    }

    /// Re-checks permissions, loads the saved combinations and installs the key listener.
    @discardableResult
    func startHotkeys() -> Bool {
        accessibilityGranted = TextInserter.isTrusted
        let settings = store.settings
        hotkeys.pushToTalk = settings.hotkeys(for: .pushToTalk)
        let actions: [(HotkeyMonitor.Trigger, HotkeyAction)] = [
            (.handsFree, .handsFree), (.editSelection, .editSelection),
            (.pasteLast, .pasteLast), (.scratchpad, .scratchpad),
        ]
        hotkeys.triggers =
            actions.flatMap { trigger, action in
                settings.hotkeys(for: action).map { (trigger: trigger, hotkey: $0) }
            }
            + settings.transforms.compactMap { transform in
                transform.hotkey.map { (trigger: .transform(transform.id), hotkey: $0) }
            }
        return accessibilityGranted && hotkeys.start()
    }

    func setHotkeysPaused(_ paused: Bool) {
        hotkeys.isPaused = paused
    }

    private func handle(_ trigger: HotkeyMonitor.Trigger) {
        switch trigger {
        case .handsFree: toggleHandsFree()
        case .editSelection: toggleCommand()
        case .pasteLast: pasteLast()
        case .scratchpad: scratchpad.toggle()
        case .transform(let id):
            if let transform = store.settings.transforms.first(where: { $0.id == id }) {
                Task { await run(transform) }
            }
        }
    }

    private func currentLocale() async -> Locale {
        let requested = Locale(identifier: store.settings.localeIdentifier)
        return await SpeechEngine.bestLocale(for: requested) ?? requested
    }

    // MARK: - Starting

    func toggleHandsFree() {
        if case .listening = phase { endDictation() } else if phase == .idle { beginDictation(handsFree: true) }
    }

    func toggleCommand() {
        if case .listening = phase {
            endDictation()
        } else if phase == .idle {
            Task { await beginCommand() }
        }
    }

    func lockHandsFree() {
        if case .listening(_, let command) = phase {
            phase = .listening(handsFree: true, command: command)
        }
    }

    private func beginDictation(handsFree: Bool) {
        guard phase == .idle else { return }
        commandSelection = nil
        start(handsFree: handsFree, command: false)
    }

    private func beginCommand() async {
        guard TextInserter.isTrusted else { return showMessage("Allow Accessibility access first") }
        guard let selection = await TextInserter.copySelection() else {
            return showMessage("Select some text first, then try again")
        }
        guard phase == .idle else { return }
        commandSelection = selection
        start(handsFree: true, command: true)
    }

    private func start(handsFree: Bool, command: Bool) {
        let settings = store.settings
        targetApp = NSWorkspace.shared.frontmostApplication
        targetHost = TextInserter.isTrusted ? FocusContext.webHost(for: targetApp) : nil
        contextTerms =
            settings.useTextBoxContext && TextInserter.isTrusted
            ? ContextNames.extract(from: FocusContext.focusedText ?? "") : []
        partial = ""
        level = 0
        stopRequested = false
        speechReady = false
        startedAt = Date()
        phase = .listening(handsFree: handsFree, command: command)
        // Show the HUD at once. It's the only signal that the key press registered.
        hud.update()
        if settings.playSounds { NSSound(named: "Tink")?.play() }
        if settings.muteWhileDictating { SystemAudio.muteOutput() }

        startTask = Task {
            do {
                guard await MicrophoneAccess.request() else {
                    throw DictationFailure("Allow microphone access for LahLah Voice in System Settings")
                }
                let locale = await currentLocale()
                // Start hearing right away. The recogniser catches up once it's ready.
                speech.beginBuffering()
                try capture.start()
                capture.isForwarding = true
                try await speech.start(
                    locale: locale, vocabulary: store.dictionary.map(\.term) + contextTerms)
                // Cancelled while starting: don't leave the microphone running.
                guard !Task.isCancelled, isActive else {
                    stopListening()
                    await speech.cancel()
                    return
                }
                speechReady = true
                if stopRequested { await finish() }
            } catch {
                stopListening()
                await speech.cancel()
                phase = .idle
                hud.update()
                showMessage(error.localizedDescription)
            }
        }
    }

    private func stopListening() {
        capture.stop()
        SystemAudio.restoreOutput()
    }

    // MARK: - Finishing

    func endDictation() {
        guard case .listening = phase else { return }
        stopRequested = true
        guard speechReady else { return }  // `start` picks this up when it's ready.
        Task { await finish() }
    }

    func cancel() {
        guard isActive else { return }
        stopListening()
        startTask?.cancel()
        Task { await speech.cancel() }
        phase = .idle
        hud.update()
    }

    private func finish() async {
        guard case .listening(_, let command) = phase else { return }
        let duration = Date().timeIntervalSince(startedAt)
        stopListening()

        // A tap too short to contain speech is just a stray key press.
        if duration < 0.3 {
            await speech.cancel()
            phase = .idle
            hud.update()
            return
        }

        if store.settings.playSounds { NSSound(named: "Pop")?.play() }
        phase = .working
        hud.update()
        let raw = await speech.finish()
        let locale = await currentLocale()

        if command {
            await applyCommand(raw, locale: locale)
        } else {
            await applyDictation(raw, locale: locale, duration: duration)
        }
        phase = .idle
        hud.update()
    }

    private func applyDictation(_ raw: String, locale: Locale, duration: Double) async {
        guard !raw.isEmpty else { return showMessage("Didn't catch that") }

        let settings = store.settings
        let command = settings.pressEnterCommand ? VoiceCommands.splitPressEnter(raw) : (raw, false)
        let bundleID = targetApp?.bundleIdentifier
        let style = AppCatalog.style(forBundleID: bundleID, host: targetHost, settings: settings)
        let result = await pipeline.process(
            raw: command.0, style: style, category: AppCatalog.category(forBundleID: bundleID, host: targetHost),
            locale: locale, dictionary: store.dictionary, snippets: store.snippets,
            useAppleIntelligence: settings.useAppleIntelligence, contextTerms: contextTerms)

        if result.text.isEmpty {
            // "Press enter" on its own.
            if command.1 { paste("", thenPressEnter: true) }
            return
        }

        paste(result.text, thenPressEnter: command.1)
        store.record(
            DictationRecord(
                raw: raw, final: result.text, appName: targetHost ?? targetApp?.localizedName,
                durationSeconds: duration, usedAppleIntelligence: result.usedAppleIntelligence))
    }

    private func applyCommand(_ instruction: String, locale: Locale) async {
        guard let selection = commandSelection, !instruction.isEmpty else { return }
        guard AppleIntelligenceEditor.status == .available else {
            return showMessage("Voice edits need Apple Intelligence")
        }
        guard
            let rewritten = await AppleIntelligenceEditor().rewrite(
                selection, instruction: instruction, locale: locale)
        else { return showMessage("Apple Intelligence couldn't make that edit") }
        paste(rewritten)
    }

    /// Rewrites the selected text with a saved instruction.
    private func run(_ transform: TextTransform) async {
        guard phase == .idle else { return }
        guard TextInserter.isTrusted else { return showMessage("Allow Accessibility access first") }
        guard AppleIntelligenceEditor.status == .available else {
            return showMessage("Transforms need Apple Intelligence")
        }
        targetApp = NSWorkspace.shared.frontmostApplication
        guard let selection = await TextInserter.copySelection() else {
            return showMessage("Select some text first, then try again")
        }
        phase = .working
        hud.update()
        let locale = await currentLocale()
        let rewritten = await AppleIntelligenceEditor().rewrite(
            selection, instruction: transform.prompt, locale: locale)
        phase = .idle
        hud.update()
        guard let rewritten else { return showMessage("Apple Intelligence couldn't do that") }
        paste(rewritten)
    }

    func pasteLast() {
        guard let last = store.history.first else { return showMessage("Nothing to paste yet") }
        targetApp = NSWorkspace.shared.frontmostApplication
        paste(last.final)
    }

    func paste(_ text: String, thenPressEnter: Bool = false) {
        targetApp?.activate()
        guard TextInserter.isTrusted else {
            TextInserter.putOnClipboard(text)
            return showMessage("Copied. Allow Accessibility access to paste automatically")
        }
        Task {
            // Give the target app focus back before checking what's focused.
            try? await Task.sleep(for: .milliseconds(40))
            if text.isEmpty {
                if thenPressEnter { TextInserter.pressReturn() }
                return
            }
            if TextInserter.focusIsSecureField {
                TextInserter.putOnClipboard(text)
                return showMessage("That's a password field, so your text is on the clipboard instead")
            }
            switch await TextInserter.paste(text) {
            case .notConfirmed:
                // Never press Return when the text didn't arrive: it could send the wrong thing.
                showMessage("No text box in focus. Your text is on the clipboard: press ⌘V")
            case .pasted:
                if thenPressEnter { TextInserter.pressReturn() }
            }
        }
    }

    private func showMessage(_ message: String) {
        lastMessage = message
        hud.flash(message)
    }
}

struct DictationFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
