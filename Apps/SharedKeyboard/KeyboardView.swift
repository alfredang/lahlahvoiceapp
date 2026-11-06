import NovaVoiceBridge
import Observation
import SwiftUI

/// State for the keyboard. The app's setup screen uses the same view as a live preview.
@MainActor
@Observable
final class KeyboardModel {
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, once, locked }

    var layer: Layer = .letters
    var shift: Shift = .once
    var sessionState: SessionState = .inactive
    var level: Float = 0
    var hint: String?
    var style: WritingStyle = .casual
    var hasFullAccess = true
    var showsNextKeyboard = true
    var returnTitle = "return"

    var insert: (String) -> Void = { _ in }
    var deleteBackward: () -> Void = {}
    var nextKeyboard: () -> Void = {}
    var micTapped: () -> Void = {}
    var styleChanged: (WritingStyle) -> Void = { _ in }
    /// The text just before the cursor, used for double-space and auto-capitals.
    var textBeforeCursor: () -> String? = { nil }

    func tap(character: String) {
        let text = (layer == .letters && shift != .off) ? character.uppercased() : character
        insert(text)
        if shift == .once { shift = .off }
    }

    func tapSpace() {
        // Two spaces make a full stop, as on the system keyboard.
        if let before = textBeforeCursor(), before.hasSuffix(" "),
            let previous = before.dropLast().last, previous.isLetter || previous.isNumber
        {
            deleteBackward()
            insert(". ")
            shift = .once
            return
        }
        insert(" ")
        updateAutoShift()
    }

    func tapShift() {
        switch shift {
        case .off: shift = .once
        case .once: shift = .locked
        case .locked: shift = .off
        }
    }

    func updateAutoShift() {
        guard layer == .letters, shift != .locked else { return }
        guard let before = textBeforeCursor(), !before.isEmpty else {
            shift = .once
            return
        }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let endsSentence = trimmed.last.map { ".!?\n".contains($0) } ?? true
        shift = endsSentence && (before.hasSuffix(" ") || before.hasSuffix("\n")) ? .once : .off
    }
}

struct KeyboardView: View {
    @Bindable var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    private let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private let numberRows = ["1234567890", "-/:;()$&@\"", ".,?!'"]
    private let symbolRows = ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]

    private let keyHeight: CGFloat = 42
    private let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: 10) {
            voiceBar
            if let hint = model.hint {
                hintView(hint)
            } else {
                keys
            }
        }
        .padding(.horizontal, 3)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Voice bar

    private var voiceBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(WritingStyle.allCases) { style in
                    Button(style.title) {
                        model.style = style
                        model.styleChanged(style)
                    }
                }
            } label: {
                Text(model.style.title)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(keyColor, in: Capsule())
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Writing style, \(model.style.title)")

            Button(action: model.micTapped) {
                HStack(spacing: 8) {
                    micContent
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(micBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(micAccessibilityLabel)
        }
    }

    @ViewBuilder private var micContent: some View {
        switch model.sessionState {
        case .listening:
            WaveBars(level: model.level)
            Text("Tap when done")
        case .working:
            Image(systemName: "ellipsis")
            Text("Writing…")
        case .ready, .inactive:
            Image(systemName: "mic.fill")
            Text("Speak")
        }
    }

    private var micBackground: AnyShapeStyle {
        switch model.sessionState {
        case .listening: AnyShapeStyle(brandListening)
        case .working: AnyShapeStyle(Color.gray)
        default: AnyShapeStyle(brandEmber)
        }
    }

    private var micAccessibilityLabel: String {
        switch model.sessionState {
        case .listening: "Stop dictating"
        case .working: "Writing your text"
        default: "Start dictating"
        }
    }

    private func hintView(_ hint: String) -> some View {
        VStack(spacing: 12) {
            Text(hint)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Back to keyboard") { model.hint = nil }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: keyHeight * 4 + gap * 3 + 8)
    }

    // MARK: - Keys

    private var keys: some View {
        VStack(spacing: 8) {
            switch model.layer {
            case .letters:
                row(letterRows[0])
                row(letterRows[1]).padding(.horizontal, 18)
                thirdRow(letterRows[2], leading: shiftKey)
            case .numbers:
                row(numberRows[0])
                row(numberRows[1])
                thirdRow(numberRows[2], leading: layerKey("#+=", to: .symbols))
            case .symbols:
                row(symbolRows[0])
                row(symbolRows[1])
                thirdRow(symbolRows[2], leading: layerKey("123", to: .numbers))
            }
            bottomRow
        }
    }

    private func row(_ characters: String) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(characters), id: \.self) { character in
                characterKey(String(character))
            }
        }
    }

    private func thirdRow(_ characters: String, leading: some View) -> some View {
        HStack(spacing: gap) {
            leading.frame(width: 44)
            Spacer(minLength: 4)
            HStack(spacing: gap) {
                ForEach(Array(characters), id: \.self) { character in
                    characterKey(String(character))
                }
            }
            Spacer(minLength: 4)
            KeyCap(height: keyHeight, background: controlColor, repeats: true, action: model.deleteBackward) {
                Image(systemName: "delete.left")
            }
            .frame(width: 44)
            .accessibilityLabel("Delete")
        }
    }

    private func characterKey(_ character: String) -> some View {
        let shown = (model.layer == .letters && model.shift != .off) ? character.uppercased() : character
        return KeyCap(height: keyHeight, background: keyColor) {
            model.tap(character: character)
        } label: {
            Text(shown).font(.system(size: 22))
        }
        .accessibilityLabel(shown)
    }

    private var shiftKey: some View {
        KeyCap(height: keyHeight, background: model.shift == .off ? controlColor : keyColor, action: model.tapShift) {
            Image(systemName: model.shift == .locked ? "capslock.fill" : (model.shift == .once ? "shift.fill" : "shift"))
        }
        .accessibilityLabel("Shift")
    }

    private func layerKey(_ title: String, to layer: KeyboardModel.Layer) -> some View {
        KeyCap(height: keyHeight, background: controlColor, action: { model.layer = layer }) {
            Text(title).font(.system(size: 15))
        }
    }

    private var bottomRow: some View {
        HStack(spacing: gap) {
            KeyCap(height: keyHeight, background: controlColor, action: {
                model.layer = model.layer == .letters ? .numbers : .letters
                model.updateAutoShift()
            }) {
                Text(model.layer == .letters ? "123" : "ABC").font(.system(size: 15))
            }
            .frame(width: 48)

            if model.showsNextKeyboard {
                KeyCap(height: keyHeight, background: controlColor, action: model.nextKeyboard) {
                    Image(systemName: "globe")
                }
                .frame(width: 44)
                .accessibilityLabel("Next keyboard")
            }

            KeyCap(height: keyHeight, background: keyColor, action: model.tapSpace) {
                Text("space").font(.system(size: 15))
            }

            KeyCap(height: keyHeight, background: controlColor, action: {
                model.insert("\n")
                model.updateAutoShift()
            }) {
                Text(model.returnTitle).font(.system(size: 15))
            }
            .frame(width: 88)
        }
    }

    // MARK: - Colours

    private var keyColor: Color {
        scheme == .dark ? Color(white: 0.42) : .white
    }

    private var controlColor: Color {
        scheme == .dark ? Color(white: 0.26) : Color(red: 0.68, green: 0.70, blue: 0.74)
    }

    // The keyboard doesn't link the app's Brand file, so it keeps its own copies of two colours.
    private var brandEmber: Color { Color(red: 0.91, green: 0.455, blue: 0.231) }
    private var brandListening: Color { Color(red: 0.78, green: 0.27, blue: 0.14) }
}

struct WaveBars: View {
    var level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .frame(width: 2.5, height: 4 + CGFloat(level) * (index % 2 == 0 ? 12 : 8))
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

/// One key. It acts on touch-down so that fast typing never drops a letter.
struct KeyCap<Label: View>: View {
    let height: CGFloat
    let background: Color
    var repeats = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        label()
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                isPressed ? background.opacity(0.55) : background,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        startRepeating()
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func startRepeating() {
        guard repeats else { return }
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}
