import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct NovaVoiceWidgets: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
        StartSessionControl()
    }
}

/// A button for Control Center, the Lock Screen and the Action button.
struct StartSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tertiaryinfotech.novavoice.start") {
            ControlWidgetButton(action: StartVoiceSessionIntent()) {
                Label("LahLah Voice", systemImage: "mic.badge.plus")
            }
        }
        .displayName("Start Voice Session")
        .description("Opens a session so you can dictate from the LahLah Voice keyboard.")
    }
}

struct SessionLiveActivity: Widget {
    private static let listening = Color(red: 0.78, green: 0.27, blue: 0.14)
    private static let ember = Color(red: 0.91, green: 0.455, blue: 0.231)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionAttributes.self) { context in
            HStack(spacing: 12) {
                symbol(context.state.phase)
                    .font(.title3)
                    .foregroundStyle(tint(context.state.phase))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(context.state.phase)).font(.headline)
                    Text("Tap Speak on the LahLah Voice keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: EndVoiceSessionIntent()) {
                    Text("End")
                }
                .tint(Self.listening)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    symbol(context.state.phase)
                        .font(.title2)
                        .foregroundStyle(tint(context.state.phase))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context.state.phase)).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: EndVoiceSessionIntent()) {
                        Text("End")
                    }
                    .tint(Self.listening)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Tap Speak on the LahLah Voice keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                symbol(context.state.phase).foregroundStyle(tint(context.state.phase))
            } compactTrailing: {
                Text(context.state.endsAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                symbol(context.state.phase).foregroundStyle(tint(context.state.phase))
            }
        }
    }

    private func symbol(_ phase: SessionAttributes.ContentState.Phase) -> Image {
        switch phase {
        case .ready: Image(systemName: "mic")
        case .listening: Image(systemName: "waveform")
        case .working: Image(systemName: "ellipsis")
        }
    }

    private func tint(_ phase: SessionAttributes.ContentState.Phase) -> Color {
        phase == .listening ? Self.listening : Self.ember
    }

    private func title(_ phase: SessionAttributes.ContentState.Phase) -> String {
        switch phase {
        case .ready: "Voice session open"
        case .listening: "Listening"
        case .working: "Writing"
        }
    }
}
