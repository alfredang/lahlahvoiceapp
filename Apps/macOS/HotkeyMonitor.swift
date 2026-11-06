import AppKit
import Carbon.HIToolbox
import NovaVoiceCore

/// Listens for the user's chosen combinations in every app. Combinations can use keys and mouse
/// buttons, and are set on the Hotkeys page. Needs Accessibility access, which also allows pasting.
///
/// Hold to talk also has two gestures built in:
///   Double-tap   keep listening hands-free until the next press
///   Esc          cancel while listening
@MainActor
final class HotkeyMonitor {
    enum Trigger: Hashable {
        case handsFree, editSelection, pasteLast, scratchpad
        case transform(UUID)
    }

    var pushToTalk: [Hotkey] = []
    var triggers: [(trigger: Trigger, hotkey: Hotkey)] = []
    /// While a new combination is being recorded, nothing should fire.
    var isPaused = false {
        didSet { if isPaused { resetPressed() } }
    }

    var onPushToTalkDown: (() -> Void)?
    var onPushToTalkUp: (() -> Void)?
    var onLockHandsFree: (() -> Void)?
    var onTrigger: ((Trigger) -> Void)?
    var onCancel: (() -> Void)?
    var isDictationActive: (() -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private var pressed: Set<HotkeyToken> = []
    /// Key and mouse presses we used, whose matching release must also stay out of the app in front.
    private var swallowed: Set<HotkeyToken> = []
    private var firedModifierCombo: Hotkey?

    private var talkIsDown = false
    private var lastTapUp: Date?
    private var keyDownAt = Date()
    private var lockedHandsFree = false
    /// The hold was really part of another shortcut, such as Fn + Delete.
    private var holdWasCancelled = false

    /// A press shorter than this counts as a tap rather than a hold.
    private let tapThreshold: TimeInterval = 0.3
    private let doubleTapWindow: TimeInterval = 0.4
    /// Another key pressed this soon after the hold began means it was a different shortcut.
    private let otherShortcutWindow: TimeInterval = 0.6

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
            let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Returns true if the event was used and must not reach the app in front.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off if it's ever slow to respond. Turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            resetPressed()
            return false
        default:
            break
        }
        guard !isPaused else { return false }

        switch type {
        case .flagsChanged:
            handleFlags(event)
            return false
        case .keyDown:
            let token = HotkeyToken.key(Int(event.getIntegerValueField(.keyboardEventKeycode)))
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return swallowed.contains(token)
            }
            return handleDown(token, event: event)
        case .keyUp:
            return handleUp(.key(Int(event.getIntegerValueField(.keyboardEventKeycode))))
        case .otherMouseDown:
            return handleDown(.mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber))), event: event)
        case .otherMouseUp:
            return handleUp(.mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber))))
        default:
            return false
        }
    }

    private func resetPressed() {
        pressed = []
        swallowed = []
        firedModifierCombo = nil
        if talkIsDown { updateHold() }
    }

    private func handleFlags(_ event: CGEvent) {
        let modifiers = HotkeyToken.modifiers(rawFlags: event.flags.rawValue)
        // macOS can skip a key's release while a modifier is held, so don't let keys stay stuck.
        let others = modifiers.isEmpty ? pressed.filter { $0.kind == .mouse } : pressed.filter { !$0.isModifier }
        pressed = modifiers.union(others)

        updateHold()

        let combo = triggers.first { $0.hotkey.isModifierOnly && $0.hotkey.matches(pressed: pressed) }
        if let combo {
            if firedModifierCombo != combo.hotkey {
                firedModifierCombo = combo.hotkey
                fire(combo.trigger)
            }
        } else {
            firedModifierCombo = nil
        }
    }

    private func handleDown(_ token: HotkeyToken, event: CGEvent) -> Bool {
        pressed.insert(token)

        if token == .key(kVK_Escape), isDictationActive?() == true {
            lockedHandsFree = false
            // The hold key may still be down. Letting go of it must not do anything more.
            holdWasCancelled = talkIsDown
            lastTapUp = nil
            swallowed.insert(token)
            onCancel?()
            return true
        }

        if let match = triggers.first(where: { !$0.hotkey.isModifierOnly && $0.hotkey.matches(pressed: pressed) }) {
            swallowed.insert(token)
            fire(match.trigger)
            return true
        }

        let wasHolding = talkIsDown
        updateHold()
        if talkIsDown, !wasHolding {
            swallowed.insert(token)
            return true
        }
        if pushToTalk.contains(where: { $0.tokens.contains(token) }) {
            swallowed.insert(token)
            return true
        }

        // Fn + Delete and the like are other shortcuts, not dictation. Let them through and stop.
        if talkIsDown, !lockedHandsFree, !holdWasCancelled,
            Date().timeIntervalSince(keyDownAt) < otherShortcutWindow
        {
            holdWasCancelled = true
            lastTapUp = nil
            onCancel?()
        }
        return false
    }

    private func handleUp(_ token: HotkeyToken) -> Bool {
        pressed.remove(token)
        updateHold()
        return swallowed.remove(token) != nil
    }

    private func updateHold() {
        let isDown = pushToTalk.contains { $0.isHeld(pressed: pressed) }
        guard isDown != talkIsDown else { return }
        talkIsDown = isDown

        if isDown {
            keyDownAt = Date()
            holdWasCancelled = false
            if lockedHandsFree {
                // Listening hands-free: the next press ends it.
                lockedHandsFree = false
                onPushToTalkUp?()
                return
            }
            if let lastTapUp, Date().timeIntervalSince(lastTapUp) < doubleTapWindow {
                self.lastTapUp = nil
                lockedHandsFree = true
                onPushToTalkDown?()
                onLockHandsFree?()
                return
            }
            onPushToTalkDown?()
        } else {
            if lockedHandsFree { return }
            if holdWasCancelled {
                holdWasCancelled = false
                return
            }
            if Date().timeIntervalSince(keyDownAt) < tapThreshold { lastTapUp = Date() }
            onPushToTalkUp?()
        }
    }

    private func fire(_ trigger: Trigger) {
        // A hands-free combination that includes the hold key, such as Fn + Space, switches the
        // dictation that key just started to hands-free, instead of stopping it.
        if trigger == .handsFree, talkIsDown, !lockedHandsFree {
            lockedHandsFree = true
            onLockHandsFree?()
            return
        }
        if trigger == .handsFree || trigger == .editSelection { lockedHandsFree = false }
        onTrigger?(trigger)
    }
}
