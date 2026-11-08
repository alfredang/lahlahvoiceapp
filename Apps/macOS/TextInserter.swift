import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts text into whatever app has focus. This is how NovaVoice works in WhatsApp, Telegram, ChatGPT
/// and any other app with a text field: it doesn't modify those apps, it just pastes into them.
@MainActor
enum TextInserter {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Accessibility settings.
    static func promptForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    static func putOnClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    enum PasteOutcome { case pasted, notConfirmed }

    /// Pastes the text, then puts the user's clipboard back how it was.
    ///
    /// The text goes on the clipboard as a promise, which macOS only fulfils when an app asks for
    /// it. So if nothing asks (no text box had focus), we know the paste failed. The text then stays
    /// on the clipboard so the user can paste it by hand, instead of being silently lost.
    static func paste(_ text: String) async -> PasteOutcome {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        let promise = PastePromise(text: text)
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        pasteboard.declareTypes([.string, transient], owner: promise)
        // Tells clipboard managers not to record this temporary change.
        pasteboard.setString("", forType: transient)
        let ours = pasteboard.changeCount

        // Give the target app a moment to regain focus.
        try? await Task.sleep(for: .milliseconds(60))
        pressCommand(key: kVK_ANSI_V)

        // Slow apps can take a while to ask for the text, so wait up to 1.5 seconds.
        for _ in 0..<30 where !promise.wasRequested {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard promise.wasRequested else {
            if pasteboard.changeCount == ours { putOnClipboard(text) }
            return .notConfirmed
        }

        // Apps can read the clipboard more than once, so don't restore it immediately.
        try? await Task.sleep(for: .milliseconds(350))
        // If the user copied something in the meantime, that's now theirs to keep.
        if pasteboard.changeCount == ours { restore(saved, to: pasteboard) }
        return .pasted
    }

    /// True when the focused field is a password box. Dictated text must never go into one.
    static var focusIsSecureField: Bool { FocusContext.focusedElementIsSecure }

    /// Copies the current selection without disturbing the clipboard. Returns nil if nothing is selected.
    static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        pressCommand(key: kVK_ANSI_C)
        var copied: String?
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(30))
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before { restore(saved, to: pasteboard) }
        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? copied : nil
    }

    /// Presses Return in the app in front, for the "press enter" voice command.
    static func pressReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        // The hold key may still be down, and Fn or Option + Return mean something else.
        down?.flags = []
        up?.flags = []
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private static func pressCommand(key: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
        // Set flags explicitly: the push-to-talk key may still be held down.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type] = data }
            }
            return values
        }
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

/// Supplies the text only when an app actually asks for it, which is how a paste is confirmed.
private final class PastePromise: NSObject, NSPasteboardTypeOwner {
    let text: String
    private(set) var wasRequested = false

    init(text: String) {
        self.text = text
    }

    func pasteboard(_ sender: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .string else { return }
        wasRequested = true
        sender.setString(text, forType: .string)
    }
}

/// Reads what's in focus through the Accessibility API. Nothing here leaves the Mac.
@MainActor
enum FocusContext {
    /// Browsers whose page address can be used to recognise web apps such as claude.ai.
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac",
        "com.brave.Browser", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.openai.atlas",
        "ai.perplexity.comet",
    ]
    private static let otherBrowsers: Set<String> = ["com.apple.Safari"]

    /// Each read gives up quickly, so a stuck app can never hold up dictation.
    private static let timeout: Float = 0.15

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static var focusedElement: AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let value = attribute(system, kAXFocusedUIElementAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static var focusedElementIsSecure: Bool {
        guard let element = focusedElement else { return false }
        return attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
    }

    /// What's written in the focused text box. Never read from a password field.
    static var focusedText: String? {
        guard let element = focusedElement,
            attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
            let text = attribute(element, kAXValueAttribute) as? String
        else { return nil }
        return String(text.suffix(2000))
    }

    /// The focused text box, so it can be read again later. Never a password field.
    static var focusedTextElement: AXUIElement? {
        guard let element = focusedElement,
            attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
            attribute(element, kAXValueAttribute) is String
        else { return nil }
        return element
    }

    /// What a text box holds now. Nil once it's gone or isn't readable.
    static func text(of element: AXUIElement) -> String? {
        guard let text = attribute(element, kAXValueAttribute) as? String else { return nil }
        return String(text.suffix(4000))
    }

    /// The address of the page in front, if that app is a browser. Only the host name is kept.
    static func webHost(for app: NSRunningApplication?) -> String? {
        guard let app, let bundleID = app.bundleIdentifier else { return nil }
        let isChromium = chromiumBrowsers.contains(bundleID)
        guard isChromium || otherBrowsers.contains(bundleID) else { return nil }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium builds its accessibility tree only when asked.
        if isChromium {
            AXUIElementSetMessagingTimeout(application, timeout)
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        // Walk up from the focused text box to the page that contains it.
        var current = focusedElement
        for _ in 0..<40 {
            guard let element = current else { break }
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea",
                let url = attribute(element, kAXURLAttribute) as? URL
            {
                return url.host()
            }
            guard let parent = attribute(element, kAXParentAttribute),
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { break }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return nil
    }
}
