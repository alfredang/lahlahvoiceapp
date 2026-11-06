import Foundation

/// How the final text should sound. Applied by Apple Intelligence when it is available,
/// and approximated deterministically when it is not.
public enum WritingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case polished, casual, veryCasual, enthusiastic, verbatim

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .polished: "Polished"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        case .enthusiastic: "Enthusiastic"
        case .verbatim: "As spoken"
        }
    }

    public var summary: String {
        switch self {
        case .polished: "Full sentences and careful punctuation. Good for email and documents."
        case .casual: "Natural and friendly, with normal punctuation. Good for chat."
        case .veryCasual: "Lowercase and relaxed, with no final full stop. Good for close friends."
        case .enthusiastic: "Warm and upbeat, without overdoing it."
        case .verbatim: "Removes fillers and applies your corrections, but keeps your wording."
        }
    }
}

