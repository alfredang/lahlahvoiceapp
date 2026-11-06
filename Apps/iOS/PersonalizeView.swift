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
                Text("Uses Apple Intelligence on this iPhone to apply corrections and tidy your wording. Choose a keyboard style from the keyboard itself.")
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
