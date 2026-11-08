import Foundation

/// A language model that runs on this Mac instead of Apple Intelligence, such as an open model
/// downloaded from Hugging Face. It gets the same instructions and the same faithfulness check,
/// so swapping models never changes what LahLah Voice is allowed to do with the text.
public protocol LocalTextModel: Sendable {
    /// Plain text in, plain text out. Throwing (or returning junk) makes the caller keep the
    /// rule-based text, exactly as when Apple Intelligence declines.
    func respond(instructions: String, prompt: String, maxTokens: Int) async throws -> String
}

/// Which model turns what was said into what was meant.
public enum CleanupEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleIntelligence
    case localModel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .localModel: "Open model on this Mac"
        }
    }
}

/// Open models that suit dictation cleanup: instruction-following, no thinking step, and small
/// enough to answer in a second or two on Apple silicon. All are Apache 2.0.
public struct LocalModelOption: Identifiable, Hashable, Sendable {
    public let id: String  // Hugging Face repository
    public let name: String
    public let size: String
    public let note: String

    /// Tested with novavoice-eval: Qwen3.5 2B and 4B pass every intent case. Ministral 3 3B
    /// failed three, so it isn't offered.
    public static let all: [LocalModelOption] = [
        LocalModelOption(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit", name: "Qwen3.5 4B", size: "3.1 GB",
            note: "Best balance of quality and speed."),
        LocalModelOption(
            id: "mlx-community/Qwen3.5-2B-4bit", name: "Qwen3.5 2B", size: "1.8 GB",
            note: "Faster, for Macs with 8 GB of memory."),
        LocalModelOption(
            id: "mlx-community/Qwen3.5-9B-MLX-4bit", name: "Qwen3.5 9B", size: "6 GB",
            note: "Highest quality. Needs 16 GB of memory or more."),
    ]

    public static let defaultID = all[0].id

    public static func named(_ id: String) -> LocalModelOption? {
        all.first { $0.id == id }
    }
}
