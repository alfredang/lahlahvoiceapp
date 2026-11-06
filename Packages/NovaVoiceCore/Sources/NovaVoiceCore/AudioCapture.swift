@preconcurrency import AVFoundation
import Foundation

/// Reads the microphone and hands buffers to whoever is listening.
///
/// On iOS the engine stays running for the whole voice session so that the keyboard can begin
/// dictation while another app is in front. While `isForwarding` is false, buffers are dropped
/// immediately: nothing is stored or transcribed.
public final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var forwarding = false
    private var running = false

    /// Called on the audio thread for every buffer while forwarding.
    public var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// Called on the audio thread with a 0...1 level while forwarding, for the waveform.
    public var onLevel: (@Sendable (Float) -> Void)?

    public init() {
        // Plugging in headphones or connecting AirPods reconfigures the engine and stops it.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartAfterRouteChange()
        }
    }

    private func restartAfterRouteChange() {
        guard isRunning else { return }
        let wasForwarding = isForwarding
        lock.withLock { running = false }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? start()
        isForwarding = wasForwarding
    }

    public var isRunning: Bool { lock.withLock { running } }

    public var isForwarding: Bool {
        get { lock.withLock { forwarding } }
        set { lock.withLock { forwarding = newValue } }
    }

    public func start() throws {
        guard !isRunning else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // .mixWithOthers leaves music and podcasts playing during a session.
        try session.setCategory(
            .playAndRecord, mode: .measurement,
            options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: [])
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, self.isForwarding else { return }
            self.onBuffer?(buffer)
            self.onLevel?(Self.level(of: buffer))
        }
        engine.prepare()
        try engine.start()
        lock.withLock { running = true }
    }

    public func stop() {
        guard isRunning else { return }
        isForwarding = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { running = false }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = (sum / Float(count)).squareRoot()
        // Speech sits roughly between -50 dB and -10 dB.
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 40, 0), 1)
    }
}
