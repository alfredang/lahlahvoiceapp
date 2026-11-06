import Foundation

public enum SessionState: String, Sendable {
    /// No voice session. The microphone is off.
    case inactive
    /// A session is open and waiting. Audio is discarded.
    case ready
    case listening
    case working
}

/// How the keyboard and the main app talk to each other.
///
/// iOS doesn't let keyboards use the microphone, so the main app holds the audio session in the
/// background and the keyboard asks it to listen. Darwin notifications signal changes, and
/// the data travels through the shared App Group. This needs Full Access on the keyboard.
public final class SessionBridge: @unchecked Sendable {
    public static let appGroup = "group.com.tertiaryinfotech.novavoice"
    public static let shared = SessionBridge()

    public enum Signal: String, CaseIterable, Sendable {
        case startRequested, stopRequested, cancelRequested, stateChanged, resultReady

        var notificationName: CFString {
            "com.tertiaryinfotech.novavoice.\(rawValue)" as CFString
        }
    }

    private enum Key {
        static let state = "session.state"
        static let heartbeat = "session.heartbeat"
        static let partial = "session.partial"
        static let level = "session.level"
        static let resultText = "result.text"
        static let resultID = "result.id"
        static let resultDate = "result.date"
        static let style = "keyboard.style"
        static let keyboardSeen = "keyboard.seen"
    }

    /// The session is treated as gone if the app stops updating this, for example if it was killed.
    public static let heartbeatInterval: TimeInterval = 2
    private static let heartbeatTimeout: TimeInterval = 6

    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var handlers: [String: [@Sendable () -> Void]] = [:]

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroup)
    }

    /// False if the App Group can't be reached, which for the keyboard means no Full Access.
    public var isAvailable: Bool { defaults != nil }

    // MARK: - State

    public var state: SessionState {
        guard let defaults else { return .inactive }
        let stored = defaults.string(forKey: Key.state).flatMap(SessionState.init) ?? .inactive
        guard stored != .inactive else { return .inactive }
        let beat = defaults.double(forKey: Key.heartbeat)
        let age = Date().timeIntervalSince1970 - beat
        return age < Self.heartbeatTimeout ? stored : .inactive
    }

    public func publish(state: SessionState) {
        defaults?.set(state.rawValue, forKey: Key.state)
        beat()
        post(.stateChanged)
    }

    public func beat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: Key.heartbeat)
    }

    public var partial: String {
        get { defaults?.string(forKey: Key.partial) ?? "" }
        set { defaults?.set(newValue, forKey: Key.partial) }
    }

    public var level: Float {
        get { defaults?.float(forKey: Key.level) ?? 0 }
        set { defaults?.set(newValue, forKey: Key.level) }
    }

    // MARK: - Results

    public func publish(result text: String) {
        guard let defaults else { return }
        defaults.set(text, forKey: Key.resultText)
        defaults.set(UUID().uuidString, forKey: Key.resultID)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.resultDate)
        post(.resultReady)
    }

    /// Takes the latest result so that it can only ever be inserted once.
    public func takeResult() -> String? {
        guard let defaults, let text = defaults.string(forKey: Key.resultText) else { return nil }
        defaults.removeObject(forKey: Key.resultText)
        // A result nobody picked up shouldn't appear in a different chat later on.
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Key.resultDate)
        return age < 60 ? text : nil
    }

    // MARK: - Keyboard

    public var style: WritingStyle {
        get { defaults?.string(forKey: Key.style).flatMap(WritingStyle.init) ?? .casual }
        set { defaults?.set(newValue.rawValue, forKey: Key.style) }
    }

    /// The keyboard records when it last ran with Full Access, so the app can show setup progress.
    public func markKeyboardSeen() {
        defaults?.set(Date().timeIntervalSince1970, forKey: Key.keyboardSeen)
    }

    public var keyboardHasRunWithFullAccess: Bool {
        (defaults?.double(forKey: Key.keyboardSeen) ?? 0) > 0
    }

    // MARK: - Signals

    public func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.notificationName), nil, nil, true)
    }

    public func observe(_ signal: Signal, handler: @escaping @Sendable () -> Void) {
        let isFirst: Bool = lock.withLock {
            let first = handlers[signal.rawValue] == nil
            handlers[signal.rawValue, default: []].append(handler)
            return first
        }
        guard isFirst else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let bridge = Unmanaged<SessionBridge>.fromOpaque(observer).takeUnretainedValue()
                bridge.deliver(name.rawValue as String)
            },
            signal.notificationName, nil, .deliverImmediately)
    }

    private func deliver(_ fullName: String) {
        guard let raw = fullName.split(separator: ".").last.map(String.init) else { return }
        let current = lock.withLock { handlers[raw] ?? [] }
        current.forEach { $0() }
    }
}
