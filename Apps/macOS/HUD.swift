import AppKit
import NovaVoiceCore
import SwiftUI

/// The small pill at the bottom of the screen. It never takes focus from the app being typed into.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private weak var controller: DictationController?
    private var message: String?
    private var hideTask: Task<Void, Never>?

    func bind(to controller: DictationController) {
        self.controller = controller
    }

    func update() {
        guard let controller else { return }
        if controller.isActive {
            hideTask?.cancel()
            message = nil
            show()
        } else if message == nil {
            panel?.orderOut(nil)
        }
    }

    func flash(_ message: String) {
        self.message = message
        show()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self.message = nil
            self.update()
        }
    }

    private func show() {
        guard let controller else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = ClickThroughHostingView(rootView: HUDView(message: message).environment(controller))
        // Only clickable while listening, for the Send button. Otherwise clicks pass through.
        if case .listening(_, false) = controller.phase, message == nil {
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = true
        }
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private func position(_ panel: NSPanel) {
        // Follow the mouse so the pill appears on the screen being used.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 4))
    }
}

/// Takes the first click, so Send works without first activating LahLah Voice. The panel is
/// non-activating, so the app being written in keeps focus and receives the text.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct HUDView: View {
    let message: String?
    @Environment(DictationController.self) private var controller

    var body: some View {
        HStack(spacing: 12) {
            NovaMark(size: 30)
            content
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: 56)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.hairline))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .foregroundStyle(Brand.ink)
        .environment(\.colorScheme, .light)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        if let message {
            Text(message).font(.callout)
        } else {
            switch controller.phase {
            case .listening(_, let command):
                if command {
                    VoiceWave(level: controller.level, barCount: 13)
                    Text("Say your edit").font(.callout.weight(.medium))
                } else {
                    if controller.partial.isEmpty {
                        VoiceWave(level: controller.level)
                    } else {
                        VoiceWave(level: controller.level, barCount: 13)
                        Text(String(controller.partial.suffix(30)))
                            .font(.callout)
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }
                    sendButton
                }
            case .working:
                Image(systemName: "ellipsis").symbolEffect(.pulse)
                Text("Writing").font(.callout.weight(.medium))
            case .idle:
                EmptyView()
            }
        }
    }

    /// Finishes, pastes and presses Return, like sending a voice message.
    private var sendButton: some View {
        Button {
            controller.finishAndSend()
        } label: {
            Label("Send", systemImage: "arrow.up")
                .font(.callout.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Brand.ember, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Send (Space while hands-free)")
    }
}
