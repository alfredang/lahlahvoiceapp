import NovaVoiceBridge
import SwiftUI
import UIKit

/// The NovaVoice keyboard: a normal typing keyboard with a Speak button.
///
/// Typing works on its own, with no Full Access and no network. Speaking needs Full Access, so
/// the keyboard can reach the voice session running in the NovaVoice app.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private let bridge = SessionBridge.shared
    private var host: UIHostingController<KeyboardView>?
    /// Set when this keyboard asked for dictation, so it only ever inserts its own result.
    private var awaitingResult = false
    private var levelTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureModel()

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host

        if hasFullAccess {
            bridge.observe(.stateChanged) { [weak self] in
                DispatchQueue.main.async { self?.refreshSession() }
            }
            bridge.observe(.resultReady) { [weak self] in
                DispatchQueue.main.async { self?.insertResult() }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.showsNextKeyboard = needsInputModeSwitchKey
        if hasFullAccess {
            bridge.markKeyboardSeen()
            model.style = bridge.style
        }
        updateReturnKey()
        model.updateAutoShift()
        refreshSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        levelTimer?.invalidate()
        levelTimer = nil
        // Leaving the text field ends any dictation that's still listening.
        if awaitingResult, bridge.state == .listening { bridge.post(.cancelRequested) }
        awaitingResult = false
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        updateReturnKey()
        model.updateAutoShift()
    }

    private func configureModel() {
        model.insert = { [weak self] in self?.textDocumentProxy.insertText($0) }
        model.deleteBackward = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        model.nextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        model.textBeforeCursor = { [weak self] in self?.textDocumentProxy.documentContextBeforeInput }
        model.micTapped = { [weak self] in self?.micTapped() }
        model.styleChanged = { [weak self] style in
            guard let self, self.hasFullAccess else { return }
            self.bridge.style = style
        }
    }

    private func updateReturnKey() {
        switch textDocumentProxy.returnKeyType {
        case .send: model.returnTitle = "send"
        case .search, .google, .yahoo: model.returnTitle = "search"
        case .go: model.returnTitle = "go"
        case .done: model.returnTitle = "done"
        case .next: model.returnTitle = "next"
        default: model.returnTitle = "return"
        }
    }

    // MARK: - Dictation

    private func micTapped() {
        guard hasFullAccess else {
            model.hint = "To speak, turn on Full Access: Settings › General › Keyboard › Keyboards › LahLah Voice. You can keep typing without it."
            return
        }
        switch bridge.state {
        case .inactive:
            // App Review 4.4.1: keyboards can't launch other apps, so this explains the next step.
            model.hint = "Start a voice session first: open LahLah Voice, or use its Control Center button, Action button or Siri. Then come back and tap Speak."
        case .ready:
            model.hint = nil
            awaitingResult = true
            bridge.post(.startRequested)
        case .listening:
            bridge.post(.stopRequested)
        case .working:
            break
        }
    }

    private func refreshSession() {
        guard hasFullAccess else {
            model.sessionState = .inactive
            return
        }
        let state = bridge.state
        model.sessionState = state
        if state != .inactive { model.hint = nil }

        if state == .listening, levelTimer == nil {
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.model.level = self.bridge.level
            }
        } else if state != .listening {
            levelTimer?.invalidate()
            levelTimer = nil
            model.level = 0
        }
    }

    private func insertResult() {
        guard awaitingResult, let text = bridge.takeResult() else { return }
        awaitingResult = false
        textDocumentProxy.insertText(text)
        model.updateAutoShift()
    }
}
