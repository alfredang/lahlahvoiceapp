import NovaVoiceCore
import SwiftUI

struct PersonalizeView: View {
    @Environment(NovaStore.self) private var store
    @State private var locales: [Locale] = []
    @State private var showClearConfirmation = false
    @State private var showSetup = false

    var body: some View {
        @Bindable var store = store
        List {
            Section("Make it yours") {
                NavigationLink { DictionaryView() } label: {
                    LabeledContent("Dictionary", value: "\(store.dictionary.count)")
                }
                NavigationLink { SnippetsView() } label: {
                    LabeledContent("Snippets", value: "\(store.snippets.count)")
                }
            }

            Section {
                Picker("Language", selection: $store.settings.localeIdentifier) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(SpeechEngine.displayName(for: locale)).tag(locale.identifier)
                    }
                }
                Picker("Style in this app", selection: $store.settings.defaultStyle) {
                    ForEach(WritingStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Understand what I meant", isOn: $store.settings.useAppleIntelligence)
            } header: {
                Text("Dictation")
            } footer: {
                Text("Applies your corrections and tidies your wording on this iPhone. Choose a keyboard style from the keyboard itself.")
            }

            if store.settings.useAppleIntelligence {
                ModelSection()
            }

            Section {
                Picker("Close when idle after", selection: $store.settings.sessionMinutes) {
                    ForEach([2, 5, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } header: {
                Text("Voice session")
            } footer: {
                Text("The microphone stays on during a session, and the orange dot and Live Activity show this. Audio between dictations is discarded, never stored.")
            }

            Section("Privacy") {
                Toggle("Keep dictation history", isOn: $store.settings.keepHistory)
                Button("Clear history", role: .destructive) { showClearConfirmation = true }
                    .disabled(store.history.isEmpty)
            }

            Section {
                Button("Set up the keyboard") { showSetup = true }
            }
        }
        .brandListBackground()
        .navigationTitle("Personalize")
        .confirmationDialog("Clear all dictation history?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { store.clearHistory() }
        }
        .sheet(isPresented: $showSetup) {
            NavigationStack { SetupView() }
        }
        .task {
            locales = await SpeechEngine.supportedLocales()
            let saved = Locale(identifier: store.settings.localeIdentifier)
            if !locales.contains(where: { $0.identifier == saved.identifier }),
                let best = await SpeechEngine.bestLocale(for: saved)
            {
                store.settings.localeIdentifier = best.identifier
            }
        }
    }
}

/// Primary model and fallback: Apple Intelligence and Qwen, both on this iPhone.
private struct ModelSection: View {
    @Environment(NovaStore.self) private var store
    private var models: LocalModelManager { .shared }

    private enum Choice: Hashable { case none, apple, qwen }

    var body: some View {
        Section {
            Picker("Primary model", selection: primary) {
                Text(CleanupEngine.appleIntelligence.title).tag(Choice.apple)
                Text(qwenTitle).tag(Choice.qwen)
            }
            Picker("Fallback model", selection: fallback) {
                Text("None").tag(Choice.none)
                if store.settings.cleanupEngine == .localModel {
                    Text(CleanupEngine.appleIntelligence.title).tag(Choice.apple)
                } else {
                    Text(qwenTitle).tag(Choice.qwen)
                }
            }
            if store.settings.usesLocalModel { status }
        } header: {
            Text("Model")
        } footer: {
            Text("The fallback is used when the primary model is unavailable, declines or changes your meaning. Both run on this iPhone, and nothing you say is sent anywhere.")
        }
        .onAppear { models.refresh(for: store.settings) }
    }

    private var qwenTitle: String {
        guard let option = LocalModelManager.options.first else { return "Qwen" }
        return "\(option.name) · \(option.size)"
    }

    @ViewBuilder private var status: some View {
        switch models.state {
        case .notDownloaded:
            Button("Download \(qwenTitle)") { models.download(store.settings.localModelID) }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction)
                Text("Downloading once from Hugging Face. Keep LahLah Voice open; Apple Intelligence is used until it's ready.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .ready:
            Label("Ready on this iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't download: \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try again") { models.download(store.settings.localModelID) }
            }
        }
    }

    /// Picking Qwen points the setting at the iPhone's model and offers the download.
    private func useQwen() {
        store.settings.localModelID = LocalModelManager.defaultID
        models.refresh(for: store.settings)
    }

    private var primary: Binding<Choice> {
        Binding {
            store.settings.cleanupEngine == .localModel ? .qwen : .apple
        } set: { choice in
            if choice == .qwen {
                store.settings.cleanupEngine = .localModel
                if store.settings.fallbackEngine == .localModel { store.settings.fallbackEngine = .appleIntelligence }
                useQwen()
            } else {
                store.settings.cleanupEngine = .appleIntelligence
                if store.settings.fallbackEngine == .appleIntelligence { store.settings.fallbackEngine = nil }
            }
        }
    }

    private var fallback: Binding<Choice> {
        Binding {
            switch store.settings.fallbackEngine {
            case .none: .none
            case .appleIntelligence: .apple
            case .localModel: .qwen
            }
        } set: { choice in
            switch choice {
            case .none: store.settings.fallbackEngine = nil
            case .apple: store.settings.fallbackEngine = .appleIntelligence
            case .qwen:
                store.settings.fallbackEngine = .localModel
                useQwen()
            }
        }
    }
}
