import AppKit
import NovaVoiceCore
import NovaVoiceLocalModel
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

    private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { broadcastState() } }
    }
    private(set) var level: Float = 0
    private(set) var partial = ""
    private(set) var lastMessage: String?
    private(set) var accessibilityGranted = TextInserter.isTrusted

    private let store: NovaStore
    private let capture = AudioCapture()
    private let speech = SpeechEngine()
    /// The open model, when chosen instead of Apple Intelligence.
    enum LocalModelState: Equatable {
        case notLoaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var localModelState: LocalModelState = .notLoaded
    @ObservationIgnored private var localModel: MLXCleanupModel?
    private let hotkeys = HotkeyMonitor()
    private let hud = HUDController()
    private let scratchpad: ScratchpadController
    /// Set by the menu bar icon, which is always on screen, so the window can open from a hotkey.
    @ObservationIgnored var openMainWindow: (() -> Void)?

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
    /// Press Return once the text is in: chosen with Space, the Send button or the mic button.
    private var sendWhenDone = false
    /// Looks for the user's corrections to the last paste, to learn those words.
    private var correctionCheck: Task<Void, Never>?
    /// Normal dictation, or every utterance goes to LahLah Video as a command (set through the API).
    var mode: VoiceMode = .normal
    /// The local control API (Settings › API).
    let control = ControlServer()

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

    // MARK: - Open model

    /// The open model to edit with, once it's on this Mac. Until then Apple Intelligence is used,
    /// so a dictation never waits for a download.
    var activeLocalModel: (any LocalTextModel)? {
        guard store.settings.usesLocalModel, localModelState == .ready,
            let localModel, localModel.modelID == store.settings.localModelID
        else { return nil }
        return localModel
    }

    /// Downloads the chosen open model the first time, then loads it.
    func prepareLocalModel() {
        let id = store.settings.localModelID
        if localModel?.modelID != id {
            if let old = localModel { Task { await old.unload() } }
            localModel = MLXCleanupModel(modelID: id)
            localModelState = .notLoaded
        }
        guard let model = localModel else { return }
        switch localModelState {
        case .downloading, .ready: return
        case .notLoaded, .failed: break
        }
        localModelState = .downloading(0)
        Task {
            do {
                try await model.load { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.localModel === model,
                            case .downloading = self.localModelState
                        else { return }
                        self.localModelState = .downloading(fraction)
                    }
                }
                if localModel === model { localModelState = .ready }
            } catch {
                if localModel === model { localModelState = .failed(error.localizedDescription) }
            }
        }
    }

    func activate() {
        if store.settings.usesLocalModel { prepareLocalModel() }
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
        hotkeys.spaceSends = { [weak self] in
            guard let self, store.settings.spaceToSend else { return false }
            return phase == .listening(handsFree: true, command: false)
        }
        hotkeys.onSend = { [weak self] in self?.finishAndSend() }

        startHotkeys()
        listenForRemoteToggle()
        control.handler = self
        control.isEnabled = { [weak self] in self?.store.settings.apiEnabled ?? false }
        control.start()
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
            (.pasteLast, .pasteLast), (.scratchpad, .scratchpad), (.openApp, .openApp),
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

    // MARK: - Mic buttons in Wiki LLM and Planner

    /// Their agent panels have a mic button that starts and stops hands-free dictation.
    private func listenForRemoteToggle() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(RemoteControl.toggleDictation), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Only from the app in front, so a background process can't turn the mic on.
                guard RemoteControl.isAllowed(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
                else { return }
                guard let self else { return }
                if case .listening(_, false) = self.phase { self.finishAndSend() } else { self.toggleHandsFree() }
            }
        }
    }

    /// Tells the mic button what's happening. Only sent while dictating into one of those apps.
    private func broadcastState() {
        guard RemoteControl.isAllowed(targetApp?.bundleIdentifier) else { return }
        let state =
            switch phase {
            case .idle: "idle"
            case .listening: "listening"
            case .working: "working"
            }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(RemoteControl.state), object: state, userInfo: nil, deliverImmediately: true)
    }

    private func handle(_ trigger: HotkeyMonitor.Trigger) {
        switch trigger {
        case .handsFree: toggleHandsFree()
        case .editSelection: toggleCommand()
        case .pasteLast: pasteLast()
        case .scratchpad: scratchpad.toggle()
        case .openApp: openMainWindow?()
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
        sendWhenDone = false
        correctionCheck?.cancel()
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

    /// Finishes the dictation and presses Return after pasting, so a chat or agent gets it at once.
    func finishAndSend() {
        guard case .listening(_, false) = phase else { return }
        sendWhenDone = true
        endDictation()
    }

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
        if mode == .lahlahVideoCommand {
            forwardToLahLahVideo(raw)
            return
        }
        if settings.lahlahVideoCommands, sendToLahLahVideo(raw) { return }
        let command = settings.pressEnterCommand ? VoiceCommands.splitPressEnter(raw) : (raw, false)
        let bundleID = targetApp?.bundleIdentifier
        let style = AppCatalog.style(forBundleID: bundleID, host: targetHost, settings: settings)
        let category = AppCatalog.category(forBundleID: bundleID, host: targetHost)
        // Primary model, then the fallback. While the open model is still downloading, Apple
        // Intelligence stands in, so a dictation never waits for it.
        let localModel = activeLocalModel
        var order = settings.engineOrder
        if localModel == nil, !order.contains(.appleIntelligence) { order.append(.appleIntelligence) }
        let result = await DictationPipeline(localModel: localModel, order: order).process(
            raw: command.0, style: style, category: category,
            locale: locale, dictionary: store.dictionary, snippets: store.snippets,
            useAppleIntelligence: settings.useAppleIntelligence, contextTerms: contextTerms,
            personalContext: PersonalContext.instructions(
                notes: settings.personalNotes, writingSample: settings.writingSample,
                category: category, style: style))

        // Wiki LLM and Planner send straight away, like a voice message in WhatsApp.
        let send =
            command.1 || sendWhenDone || (settings.sendInAgentApps && RemoteControl.isAllowed(bundleID))
        if result.text.isEmpty {
            // "Press enter" on its own.
            if send { paste("", thenPressEnter: true) }
            return
        }

        paste(result.text, thenPressEnter: send, learnFromEdits: !send)
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

    func paste(_ text: String, thenPressEnter: Bool = false, learnFromEdits: Bool = false) {
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
                if learnFromEdits, store.settings.learnCorrections { watchForCorrections(of: text) }
            }
        }
    }

    // MARK: - Learning from corrections

    /// Reads the text box a few times over the next minute. If the user fixed a word in what was
    /// pasted, that word goes in the dictionary, which the recogniser is given as vocabulary.
    private func watchForCorrections(of pasted: String) {
        correctionCheck?.cancel()
        guard let element = FocusContext.focusedTextElement else { return }
        correctionCheck = Task { [weak self] in
            // Checks at about 6, 15, 30 and 60 seconds after the paste.
            for delay in [6, 9, 15, 30] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                guard let text = FocusContext.text(of: element) else { return }
                let known = store.dictionary.map(\.term)
                let learned = CorrectionLearner.learnedWords(pasted: pasted, fieldText: text, known: known)
                if !learned.isEmpty {
                    store.dictionary.append(contentsOf: learned.map { DictionaryEntry(term: $0) })
                    let list = learned.map { "“\($0)”" }.joined(separator: ", ")
                    showMessage("Added \(list) to your dictionary")
                    return
                }
            }
        }
    }

    // MARK: - Fn key

    /// True when pressing Fn also does something of its own, such as opening Emoji & Symbols.
    /// Then each press for dictation moves focus to that window, and the text goes there.
    var fnKeyHasSystemAction: Bool {
        let usesFn = store.settings.hotkeys(for: .pushToTalk).contains { $0.tokens.contains(.fn) }
            || store.settings.hotkeys(for: .handsFree).contains { $0.tokens.contains(.fn) }
        return usesFn && FnKeySetting.current != .doNothing
    }

    /// LahLah Video commands: runs the words as an editing command instead of typing them.
    /// Returns false when the words are not meant for LahLah Video.
    private func sendToLahLahVideo(_ raw: String) -> Bool {
        guard let command = LahLahVideoCommands.command(from: raw, frontmostBundleID: targetApp?.bundleIdentifier)
        else { return false }
        forwardToLahLahVideo(command)
        return true
    }

    private func forwardToLahLahVideo(_ text: String) {
        Task {
            let delivery = await deliverToLahLahVideo(text)
            showMessage(delivery.ok ? "LahLah Video: \(delivery.message)" : delivery.message)
        }
    }

    /// LahLah Video's API first (it answers with what it did), the lahlahvideo:// link as the fallback.
    func deliverToLahLahVideo(_ text: String) async -> LahLahVideoDelivery {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let viaAPI = await LahLahVideoLink.sendViaAPI(command) { return viaAPI }
        guard let url = LahLahVideoCommands.url(for: command), NSWorkspace.shared.open(url) else {
            return LahLahVideoDelivery(ok: false, via: "deep-link", message: "Install LahLah Video to use video commands")
        }
        return LahLahVideoDelivery(ok: true, via: "deep-link", message: command)
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

// MARK: - Local API (Settings › API)

extension DictationController: VoiceAPIHandler {
    private var phaseName: String {
        switch phase {
        case .idle: "idle"
        case .listening: "listening"
        case .working: "working"
        }
    }

    func apiStatus() -> VoiceAPIStatus {
        VoiceAPIStatus(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            phase: phaseName, mode: mode, lastTranscript: store.history.first?.final,
            lahlahVideoAvailable: LahLahVideoLink.readControl() != nil)
    }

    func apiStartDictation() -> String {
        if phase == .idle { beginDictation(handsFree: true) }
        return phaseName
    }

    func apiStopDictation() -> String {
        if case .listening = phase { endDictation() }
        return phaseName
    }

    func apiLastTranscript() -> DictationRecord? { store.history.first }

    func apiSetMode(_ mode: VoiceMode) {
        self.mode = mode
        showMessage(mode == .lahlahVideoCommand ? "Voice now edits in LahLah Video" : "Back to normal dictation")
    }

    func apiSendToLahLahVideo(_ text: String) async -> LahLahVideoDelivery {
        await deliverToLahLahVideo(text)
    }
}
