import ActivityKit
import Foundation

/// The Live Activity that shows, whenever a voice session is open, that the microphone is in use.
struct SessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case ready, listening, working }
        var phase: Phase
        var endsAt: Date
    }
}
