import AppKit

/// macOS's own "Press 🌐 key to" setting (System Settings > Keyboard).
///
/// Unless it's "Do Nothing", pressing Fn also opens Emoji & Symbols, switches input source or
/// starts Apple's dictation. That window takes focus, so dictated text lands in its search box
/// instead of the app being written in.
enum FnKeySetting: Equatable {
    case doNothing, changeInputSource, emojiAndSymbols, appleDictation, unknown

    static var current: FnKeySetting {
        // Unset means the system default, which opens Emoji & Symbols on Macs with a 🌐 key.
        let value = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        switch value {
        case 0: return .doNothing
        case 1: return .changeInputSource
        case nil, 2: return .emojiAndSymbols
        case 3: return .appleDictation
        default: return .unknown
        }
    }

    var title: String {
        switch self {
        case .doNothing: "Do Nothing"
        case .changeInputSource: "Change Input Source"
        case .emojiAndSymbols: "Show Emoji & Symbols"
        case .appleDictation: "Start Dictation"
        case .unknown: "something else"
        }
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
