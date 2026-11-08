import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import NovaVoiceCore
import Tokenizers

/// Runs an open model from Hugging Face on Apple silicon with MLX. The weights download once,
/// then everything runs on this device. The model stays loaded between dictations and is let go
/// after a few idle minutes, so it doesn't hold gigabytes of memory all day.
///
/// iOS doesn't let an app use the GPU in the background, where the iPhone app dictates for the
/// keyboard, so there `preferCPU` returns true and the model runs on the CPU instead.
public actor MLXCleanupModel: LocalTextModel {
    public nonisolated let modelID: String
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var unloadTask: Task<Void, Never>?
    private let idleTimeout: Duration
    private let preferCPU: @Sendable () -> Bool

    public init(
        modelID: String, idleTimeout: Duration = .seconds(300),
        preferCPU: @escaping @Sendable () -> Bool = { false }
    ) {
        self.modelID = modelID
        self.idleTimeout = idleTimeout
        self.preferCPU = preferCPU
    }

    /// Downloads (first time only) and loads the model. `progress` reports the download, 0 to 1.
    public func load(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await loadedContainer(progress: progress)
    }

    public func unload() {
        container = nil
        loading = nil
        unloadTask?.cancel()
    }

    public func respond(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let model = try await loadedContainer(progress: nil)
        defer { scheduleUnload() }
        // Greedy, short and without a thinking step: cleanup should be fast and repeatable.
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        let session = ChatSession(
            model, instructions: instructions, generateParameters: parameters,
            additionalContext: ["enable_thinking": false])
        if preferCPU() {
            return try await Device.withDefaultDevice(.cpu) { try await session.respond(to: prompt) }
        }
        return try await session.respond(to: prompt)
    }

    private func loadedContainer(progress: (@Sendable (Double) -> Void)?) async throws
        -> ModelContainer
    {
        unloadTask?.cancel()
        if let container { return container }
        if let loading { return try await loading.value }
        let configuration = ModelConfiguration(id: modelID)
        let task = Task {
            try await #huggingFaceLoadModelContainer(
                configuration: configuration,
                progressHandler: { progress?($0.fractionCompleted) })
        }
        loading = task
        do {
            let loaded = try await task.value
            container = loaded
            loading = nil
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        let timeout = idleTimeout
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }
}
