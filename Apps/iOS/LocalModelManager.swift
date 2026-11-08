import NovaVoiceCore
import NovaVoiceLocalModel
import Observation
import os
import UIKit

/// The open model on this iPhone, as the primary model or the fallback for Apple Intelligence.
/// It downloads once from Hugging Face, then loads only while dictating and is let go a minute
/// later, so it never holds memory in the background for long.
@MainActor
@Observable
final class LocalModelManager {
    static let shared = LocalModelManager()

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded
    @ObservationIgnored private var model: MLXCleanupModel?

    /// iPhone offers the 2B model: it fits in memory beside the app and answers in a second or two.
    static let options = LocalModelOption.all.filter { $0.id == "mlx-community/Qwen3.5-2B-4bit" }
    static var defaultID: String { options.first?.id ?? LocalModelOption.defaultID }

    private static let memoryNeeded = 2_500_000_000

    /// True while the app is in the background, where iOS allows no GPU work.
    private static let inBackground = OSAllocatedUnfairLock(initialState: false)

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Self.inBackground.withLock { $0 = true }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Self.inBackground.withLock { $0 = false }
        }
    }

    private func downloadedKey(_ id: String) -> String { "localModel.downloaded." + id }

    /// The model to edit with, once downloaded. It loads on first use.
    func active(for settings: NovaSettings) -> (any LocalTextModel)? {
        guard settings.usesLocalModel else { return nil }
        let id = settings.localModelID
        guard UserDefaults.standard.bool(forKey: downloadedKey(id)) else { return nil }
        // Loading needs about 2.5 GB free. With less, iOS could end the app (and the keyboard's
        // voice session) for using too much memory, so Apple Intelligence or the plain text is used.
        guard os_proc_available_memory() > Self.memoryNeeded else { return nil }
        return model(for: id)
    }

    func refresh(for settings: NovaSettings) {
        guard case .downloading = state else {
            state = UserDefaults.standard.bool(forKey: downloadedKey(settings.localModelID)) ? .ready : .notDownloaded
            return
        }
    }

    /// Downloads the model the first time (about 1.8 GB), then lets it go until it is needed.
    func download(_ id: String) {
        if case .downloading = state { return }
        let model = model(for: id)
        state = .downloading(0)
        Task {
            do {
                try await model.load { fraction in
                    Task { @MainActor in
                        if case .downloading = LocalModelManager.shared.state {
                            LocalModelManager.shared.state = .downloading(fraction)
                        }
                    }
                }
                await model.unload()
                UserDefaults.standard.set(true, forKey: downloadedKey(id))
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func model(for id: String) -> MLXCleanupModel {
        if let model, model.modelID == id { return model }
        if let old = model { Task { await old.unload() } }
        let made = MLXCleanupModel(
            modelID: id, idleTimeout: .seconds(60),
            preferCPU: { LocalModelManager.inBackground.withLock { $0 } })
        model = made
        return made
    }
}
