import SwiftUI

/// LahLah Voice's look: warm paper, dark ink and one ember accent.
enum Brand {
    static let sand = Color(red: 0.953, green: 0.945, blue: 0.922)
    static let panel = Color(red: 0.988, green: 0.984, blue: 0.973)
    static let card = Color.white
    static let ink = Color(red: 0.11, green: 0.106, blue: 0.098)
    static let muted = Color(red: 0.42, green: 0.41, blue: 0.38)
    static let hairline = Color.black.opacity(0.08)
    static let ember = Color(red: 0.91, green: 0.455, blue: 0.231)
    static let localBadge = Color(red: 0.90, green: 0.92, blue: 0.985)
    static let localText = Color(red: 0.25, green: 0.36, blue: 0.80)

    static let accent = ember
}

extension View {
    /// A white card with a thin border, the main surface throughout the app.
    func brandCard(cornerRadius: CGFloat = 14) -> some View {
        background(Brand.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Brand.hairline)
            }
    }

    /// Lets the app's paper background show behind a List or Form.
    @ViewBuilder func brandListBackground() -> some View {
        #if os(iOS)
        scrollContentBackground(.hidden).background(Brand.sand)
        #else
        scrollContentBackground(.hidden)
        #endif
    }
}

/// The logo: a microphone inside an ember ring, as on the app icon.
struct NovaMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "mic")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Brand.ink)
            .frame(width: size, height: size)
            .background(.white, in: Circle())
            .overlay { Circle().strokeBorder(Brand.ember, lineWidth: max(1.5, size * 0.07)) }
            .accessibilityHidden(true)
    }
}

/// Small live input level, for buttons and list rows.
struct WaveformView: View {
    var level: Float
    var barCount = 5
    var color: Color = .white

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }

    private func height(for index: Int) -> CGFloat {
        // The middle bars move most, which reads as a voice rather than a meter.
        let middle = Double(barCount - 1) / 2
        let weight = 1 - abs(Double(index) - middle) / (middle + 1)
        return 4 + CGFloat(Double(level) * 14 * weight)
    }
}

/// The large wave shown while listening: ink bars with an ember accent, moving with your voice.
struct VoiceWave: View {
    var level: Float
    var barCount = 27
    var maxHeight: CGFloat = 32

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(index % 4 == 0 ? Brand.ember : Brand.ink)
                        .frame(width: 3.5, height: height(index, time))
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }

    private func height(_ index: Int, _ time: Double) -> CGFloat {
        let position = Double(index) / Double(max(barCount - 1, 1))
        let shape = pow(abs(sin(position * .pi * 2)), 1.4)
        let loudness = min(1, Double(level) * 1.6)
        let ripple = 0.72 + 0.28 * sin(time * 7 + Double(index) * 0.9)
        return 5 + (maxHeight - 5) * CGFloat(shape * (0.18 + 0.82 * loudness) * ripple)
    }
}
