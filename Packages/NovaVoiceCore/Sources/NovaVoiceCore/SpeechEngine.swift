@preconcurrency import AVFoundation
import Foundation
import Speech

public enum SpeechEngineError: LocalizedError {
    case unsupportedLocale(String)
    case noAudioFormat

    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let identifier):
            "On-device speech recognition isn't available for \(identifier)."
        case .noAudioFormat:
            "The speech recogniser couldn't find a compatible audio format."
        }
    }
}

/// On-device speech recognition with Apple's SpeechAnalyzer. Audio never leaves the device.
///
/// Uses `SpeechTranscriber` where the language supports it, and `DictationTranscriber`, which covers
/// more languages, for the rest.
public final class SpeechEngine: @unchecked Sendable {
    public enum Module { case transcriber(SpeechTranscriber), dictation(DictationTranscriber) }

    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var finalized = ""
    private var volatile = ""
    /// Audio that arrives while the recogniser is still starting, so the first word isn't lost.
    private var earlyBuffers: [AVAudioPCMBuffer] = []
    private var isBufferingEarly = false

    /// Called with the running transcript, including words still being refined.
    public var onPartial: (@Sendable (String) -> Void)?

    public init() {}

    // MARK: - Languages

    public static func supportedLocales() async -> [Locale] {
        let transcriber = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        var seen = Set<String>()
        return (transcriber + dictation)
            .filter { seen.insert($0.identifier(.bcp47)).inserted }
            .sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1))
                    == .orderedAscending
            }
    }

    public static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Picks the closest supported locale for what the user asked for.
    public static func bestLocale(for requested: Locale) async -> Locale? {
        let supported = await supportedLocales()
        let wanted = requested.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == wanted }) { return exact }
        let language = requested.language.languageCode
        return supported.first { $0.language.languageCode == language }
    }

    private static func makeModule(for locale: Locale) async throws -> (any SpeechModule, Module) {
        let wanted = locale.identifier(.bcp47)
        let transcribable = await SpeechTranscriber.supportedLocales
        if let match = transcribable.first(where: { $0.identifier(.bcp47) == wanted }) {
            let module = SpeechTranscriber(
                locale: match, transcriptionOptions: [], reportingOptions: [.volatileResults],
                attributeOptions: [])
            return (module, .transcriber(module))
        }
        let dictatable = await DictationTranscriber.supportedLocales
        if let match = dictatable.first(where: { $0.identifier(.bcp47) == wanted }) {
            let module = DictationTranscriber(locale: match, preset: .progressiveShortDictation)
            return (module, .dictation(module))
        }
        throw SpeechEngineError.unsupportedLocale(locale.identifier)
    }

    // MARK: - Language pack

    /// Whether the recognition model for this language is already on the device.
    public static func isInstalled(_ locale: Locale) async -> Bool {
        guard let (module, _) = try? await makeModule(for: locale) else { return false }
        return await AssetInventory.status(forModules: [module]) == .installed
    }

    /// Downloads the on-device model for this language if needed. Safe to call repeatedly.
    public static func ensureInstalled(
        _ locale: Locale, progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let (module, _) = try await makeModule(for: locale)
        guard
            let request = try await AssetInventory.assetInstallationRequest(supporting: [module])
        else {
            progress?(1)
            return
        }
        let observer: Task<Void, Never>? = progress.map { report in
            Task {
                while !Task.isCancelled {
                    report(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        defer { observer?.cancel() }
        try await request.downloadAndInstall()
        progress?(1)
    }

    // MARK: - Session

    /// Call just before the microphone starts forwarding. Audio is held until `start` is ready.
    public func beginBuffering() {
        lock.withLock {
            earlyBuffers = []
            isBufferingEarly = true
        }
    }

    /// Starts a recognition session. Feed audio with `append`, then call `finish`.
    public func start(locale: Locale, vocabulary: [String] = []) async throws {
        await cancelCurrentAnalyzer()

        let (module, kind) = try await Self.makeModule(for: locale)
        try await Self.ensureInstalled(locale)

        guard
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        else { throw SpeechEngineError.noAudioFormat }

        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        lock.withLock {
            self.analyzer = analyzer
            self.analyzerFormat = format
            self.inputContinuation = continuation
            self.finalized = ""
            self.volatile = ""
            self.converter = nil
            self.converterInputFormat = nil
        }

        resultsTask = Task { [weak self] in
            switch kind {
            case .transcriber(let transcriber):
                do {
                    for try await result in transcriber.results {
                        self?.receive(
                            String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {}
            case .dictation(let dictation):
                do {
                    for try await result in dictation.results {
                        self?.receive(
                            String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {}
            }
        }

        try await analyzer.prepareToAnalyze(in: format)
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(vocabulary.prefix(100))
            try? await analyzer.setContext(context)
        }
        try await analyzer.start(inputSequence: stream)

        // The recogniser is live. Send what was said while it was starting, in order.
        let early: [AVAudioPCMBuffer] = lock.withLock {
            let buffers = earlyBuffers
            earlyBuffers = []
            isBufferingEarly = false
            return buffers
        }
        for buffer in early { append(buffer) }
    }

    private func receive(_ text: String, isFinal: Bool) {
        let transcript: String = lock.withLock {
            if isFinal {
                finalized += text
                volatile = ""
            } else {
                volatile = text
            }
            return finalized + volatile
        }
        onPartial?(transcript)
    }

    /// Converts a microphone buffer to the format the recogniser wants and queues it.
    /// Safe to call from the real-time audio thread's serial tap.
    public func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if isBufferingEarly {
            // Tap buffers are reused by the engine, so keep a copy. Capped at about a minute.
            if earlyBuffers.count < 1500, let copy = Self.copy(buffer) { earlyBuffers.append(copy) }
            lock.unlock()
            return
        }
        let target = analyzerFormat
        let continuation = inputContinuation
        lock.unlock()
        guard let target, let continuation else { return }

        guard let converted = convert(buffer, to: target) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
            let source = buffer.floatChannelData, let target = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        let samples = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(buffer.format.channelCount) {
            memcpy(target[channel], source[channel], samples)
        }
        return copy
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        lock.lock()
        if converterInputFormat != buffer.format || converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: format)
            // Don't prime with silence: the first syllable matters when dictation starts mid-breath.
            converter?.primeMethod = .none
            converterInputFormat = buffer.format
        }
        let converter = self.converter
        lock.unlock()
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    /// Ends the session and returns the final transcript.
    @discardableResult
    public func finish() async -> String {
        let (analyzer, continuation, task) = lock.withLock {
            (self.analyzer, self.inputContinuation, self.resultsTask)
        }
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await task?.value
        return lock.withLock {
            let text = (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
            self.analyzer = nil
            self.inputContinuation = nil
            self.resultsTask = nil
            return text
        }
    }

    /// Throws away the current session without producing a transcript.
    public func cancel() async {
        lock.withLock {
            earlyBuffers = []
            isBufferingEarly = false
        }
        await cancelCurrentAnalyzer()
    }

    private func cancelCurrentAnalyzer() async {
        let (analyzer, continuation, task) = lock.withLock {
            (self.analyzer, self.inputContinuation, self.resultsTask)
        }
        continuation?.finish()
        await analyzer?.cancelAndFinishNow()
        task?.cancel()
        lock.withLock {
            self.analyzer = nil
            self.inputContinuation = nil
            self.resultsTask = nil
            self.finalized = ""
            self.volatile = ""
        }
    }

    // MARK: - Files

    /// Transcribes an audio file through the same path as the microphone. Used for testing.
    public func transcribe(file url: URL, locale: Locale, vocabulary: [String] = []) async throws -> String {
        try await start(locale: locale, vocabulary: vocabulary)
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            append(buffer)
        }
        return await finish()
    }
}
