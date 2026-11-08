import AppKit
import CoreAudio
import NovaVoiceCore
import Observation
import SwiftUI

/// A key drawn like a physical keycap.
struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Brand.ink, lineWidth: 1)
            }
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Brand.ink)
                    .offset(y: 2)
            }
            .padding(.bottom, 2)
    }
}

/// Keycaps for one combination.
struct HotkeyCaps: View {
    let hotkey: Hotkey

    var body: some View {
        HStack(spacing: 4) {
            ForEach(hotkey.capTitles, id: \.self) { Keycap(text: $0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hotkey.title)
    }
}

/// Captures a new combination: everything held at the moment the keys are all let go.
///
/// One recorder serves every row, so only one row records at a time. Starting another row,
/// leaving the page or switching to another app ends the recording and keeps the combination
/// already pressed, so nothing is lost and no row is left stuck on "Press keys…".
@MainActor
@Observable
final class HotkeyCapture {
    static let shared = HotkeyCapture()

    private(set) var owner: UUID?
    private(set) var peak: Set<HotkeyToken> = []
    private var pressed: Set<HotkeyToken> = []
    private var monitor: Any?
    private var resignObserver: Any?
    private var onFinish: ((Hotkey?) -> Void)?

    func isRecording(_ id: UUID) -> Bool { owner == id }

    func start(owner id: UUID, onFinish: @escaping (Hotkey?) -> Void) {
        commit()
        owner = id
        self.onFinish = onFinish
        peak = []
        pressed = []
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return nil
        }
        // Key releases in another app never reach us: finish with what was pressed.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.commit() }
        }
    }

    /// Ends the recording (only `id`'s, when given), saving a combination already pressed.
    func commit(owner id: UUID? = nil) {
        guard let owner, id == nil || owner == id else { return }
        finish(peak.isEmpty ? nil : Hotkey(Array(peak)))
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        owner = nil
        peak = []
        pressed = []
    }

    private func handle(_ event: NSEvent) {
        // The 🌐 key's own press: it is recorded as Fn, from its modifier change.
        if event.type == .keyDown || event.type == .keyUp,
            event.keyCode == UInt16(HotkeyMonitor.globeKeyCode)
        { return }
        switch event.type {
        case .flagsChanged:
            let modifiers = HotkeyToken.modifiers(rawFlags: UInt64(event.modifierFlags.rawValue))
            let others = modifiers.isEmpty ? pressed.filter { $0.kind == .mouse } : pressed.filter { !$0.isModifier }
            pressed = modifiers.union(others)
        case .keyDown:
            if event.isARepeat { return }
            // Esc on its own backs out, so it can't be recorded by accident.
            if event.keyCode == 53, pressed.isEmpty { return finish(nil) }
            pressed.insert(.key(Int(event.keyCode)))
        case .keyUp:
            pressed.remove(.key(Int(event.keyCode)))
        case .otherMouseDown:
            pressed.insert(.mouse(event.buttonNumber))
        case .otherMouseUp:
            pressed.remove(.mouse(event.buttonNumber))
        default:
            return
        }
        peak.formUnion(pressed)
        if pressed.isEmpty, !peak.isEmpty { finish(Hotkey(Array(peak))) }
    }

    private func finish(_ hotkey: Hotkey?) {
        let onFinish = self.onFinish
        self.onFinish = nil
        stop()
        onFinish?(hotkey)
    }
}

/// Shows the current combinations for one action, with buttons to change them.
struct HotkeyEditor: View {
    let current: [Hotkey]
    let allowsSeveral: Bool
    let inUse: [Hotkey]
    let onChange: ([Hotkey]) -> Void

    @Environment(DictationController.self) private var controller
    @State private var id = UUID()
    private var capture: HotkeyCapture { .shared }
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(current, id: \.self) { hotkey in
                    HStack(spacing: 4) {
                        HotkeyCaps(hotkey: hotkey)
                        Button {
                            problem = nil
                            onChange(current.filter { $0 != hotkey })
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.muted.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(hotkey.title)")
                    }
                }
                if capture.isRecording(id) {
                    Text(capture.peak.isEmpty ? "Press keys… (Esc to cancel)" : Hotkey(Array(capture.peak)).title)
                        .font(.callout)
                        .foregroundStyle(Brand.ember)
                } else if allowsSeveral || current.isEmpty {
                    Button(current.isEmpty ? "Set" : "Add") { record() }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear {
            // Leaving the page keeps a combination already pressed.
            capture.commit(owner: id)
        }
    }

    private func record() {
        problem = nil
        controller.setHotkeysPaused(true)
        capture.start(owner: id) { hotkey in
            controller.setHotkeysPaused(false)
            guard let hotkey else { return }
            if let issue = hotkey.problem(existing: inUse + current) {
                problem = issue.message
            } else {
                onChange(current + [hotkey])
            }
        }
    }
}

struct HotkeysPage: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 0) {
                    ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element) { index, action in
                        if index > 0 { Divider().padding(.horizontal, 18) }
                        row(for: action)
                    }
                }
                .brandCard()

                overlapNote

                VStack(alignment: .leading, spacing: 6) {
                    Text("Good to know").font(.headline)
                    Text("Press Esc at any time to cancel a dictation.")
                    Text("Mouse buttons work too: press Add, then click a side button on your mouse.")
                    Text("Fn is the 🌐 Globe key. While it is a LahLah hotkey, it no longer opens emoji, so the pill stays. If Apple dictation still starts, set “Press 🌐 key to” to “Do Nothing” in System Settings → Keyboard.")
                }
                .font(.callout)
                .foregroundStyle(Brand.muted)
            }
            .padding(.bottom, 24)
        }
    }

    private func row(for action: HotkeyAction) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).fontWeight(.medium)
                Text(action.detail).font(.caption).foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 12)
            HotkeyEditor(
                current: store.settings.hotkeys(for: action),
                allowsSeveral: true,
                inUse: store.settings.hotkeysInUse(excluding: action),
                onChange: { hotkeys in
                    store.settings.setHotkeys(hotkeys, for: action)
                    controller.startHotkeys()
                })
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var overlapNote: some View {
        let pushToTalk = store.settings.hotkeys(for: .pushToTalk)
        if store.settings.hotkeys(for: .handsFree).contains(where: { $0.overlaps(pushToTalk: pushToTalk) }) {
            Label(
                "Your hands-free combination includes your hold-to-talk key. Pressing it starts dictating, then switches to hands-free.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(Brand.muted)
        }
    }
}

/// Saved instructions that rewrite selected text with Apple Intelligence.
struct TransformsPage: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller
    @State private var name = ""
    @State private var prompt = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("New transform").font(.headline)
                    TextField("Name, such as “Turn into bullet points”", text: $name)
                    TextField("What should it do to the selected text?", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Add transform", systemImage: "plus") { add() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                                || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .padding(16)
                .brandCard()

                VStack(spacing: 0) {
                    let transforms = store.settings.transforms
                    if transforms.isEmpty {
                        Text("Add a transform to rewrite selected text with one key press.")
                            .foregroundStyle(Brand.muted)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(transforms.enumerated()), id: \.element.id) { index, transform in
                        if index > 0 { Divider().padding(.horizontal, 18) }
                        row(for: transform)
                    }
                }
                .brandCard()
            }
            .padding(.bottom, 24)
        }
    }

    private func row(for transform: TextTransform) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transform.name).fontWeight(.medium)
                Text(transform.prompt).font(.caption).foregroundStyle(Brand.muted).lineLimit(2)
            }
            Spacer(minLength: 12)
            HotkeyEditor(
                current: transform.hotkey.map { [$0] } ?? [],
                allowsSeveral: false,
                inUse: store.settings.hotkeysInUse(transform: transform.id),
                onChange: { hotkeys in
                    guard let index = store.settings.transforms.firstIndex(where: { $0.id == transform.id }) else { return }
                    store.settings.transforms[index].hotkey = hotkeys.first
                    controller.startHotkeys()
                })
            Button {
                store.settings.transforms.removeAll { $0.id == transform.id }
                controller.startHotkeys()
            } label: {
                Image(systemName: "trash").foregroundStyle(Brand.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(transform.name)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func add() {
        store.settings.transforms.append(
            TextTransform(
                name: name.trimmingCharacters(in: .whitespaces),
                prompt: prompt.trimmingCharacters(in: .whitespaces)))
        name = ""
        prompt = ""
    }
}

/// A small floating window for rough notes. It's a normal text box, so dictating into it just works.
@MainActor
final class ScratchpadController {
    private var panel: NSPanel?
    private let store: NovaStore

    init(store: NovaStore) {
        self.store = store
    }

    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow {
            panel.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Scratchpad"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ScratchpadView(store: store))
        panel.center()
        return panel
    }
}

private struct ScratchpadView: View {
    @Bindable var store: NovaStore

    var body: some View {
        TextEditor(text: $store.settings.scratchpad)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Brand.panel)
            .environment(\.colorScheme, .light)
    }
}

/// Turns the speakers off while listening, so music doesn't get in the way, then back on.
@MainActor
enum SystemAudio {
    private static var mutedDevice: AudioObjectID?

    static func muteOutput() {
        guard mutedDevice == nil, let device = defaultOutput else { return }
        var isMuted = mute(of: device)
        // Already muted by the user, so leave it for them to turn back on.
        guard isMuted == 0 else { return }
        isMuted = 1
        if setMute(isMuted, on: device) { mutedDevice = device }
    }

    static func restoreOutput() {
        guard let device = mutedDevice else { return }
        mutedDevice = nil
        _ = setMute(0, on: device)
    }

    private static var defaultOutput: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func mute(of device: AudioObjectID) -> UInt32 {
        var address = muteAddress()
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    private static func setMute(_ value: UInt32, on device: AudioObjectID) -> Bool {
        var address = muteAddress()
        var value = value
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }
}
