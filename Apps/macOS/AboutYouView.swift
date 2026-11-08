import NovaVoiceCore
import SwiftUI

/// Notes every dictation should know, and a sample of how the user writes. Both go to the model
/// on this Mac with each dictation, so it hears "irreducible" when the topic is group theory and
/// writes in the user's own way.
struct AboutYouView: View {
    @Environment(NovaStore.self) private var store
    @State private var newNote = ""
    @State private var newCategory: AppCategory?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach($store.settings.personalNotes) { $note in
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Note", text: $note.text, axis: .vertical)
                        Picker("", selection: $note.category) {
                            Text("Every app").tag(AppCategory?.none)
                            ForEach(AppCategory.allCases) { Text($0.title).tag(AppCategory?.some($0)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button {
                            store.settings.personalNotes.removeAll { $0.id == note.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    TextField(
                        "For example: I teach group theory and representation theory.",
                        text: $newNote, axis: .vertical
                    )
                    .onSubmit(addNote)
                    Picker("", selection: $newCategory) {
                        Text("Every app").tag(AppCategory?.none)
                        ForEach(AppCategory.allCases) { Text($0.title).tag(AppCategory?.some($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Add", action: addNote)
                        .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("What LahLah Voice should know about you")
            } footer: {
                Text(
                    "Your work, the topics you talk about and how you like things written, such as British spelling. "
                        + "These help it understand words it misheard. They're never added to your text.")
            }

            Section {
                TextEditor(text: $store.settings.writingSample)
                    .font(.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                let words = PersonalContext.wordCount(store.settings.writingSample)
                Text(
                    words >= PersonalContext.minimumSampleWords
                        ? "\(words) words. Dictation will follow this style."
                        : "\(words) of at least \(PersonalContext.minimumSampleWords) words."
                )
                .font(.caption)
                .foregroundStyle(Brand.muted)
            } header: {
                Text("A sample of your writing")
            } footer: {
                Text(
                    "Paste an email, message or document you wrote. LahLah Voice matches its tone and punctuation, "
                        + "except in code editors and the \u{201C}As spoken\u{201D} style. Only the first few paragraphs are used.")
            }

            Section {
                Label("Everything here stays on this Mac and is only read by the model on this Mac.", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(Brand.muted)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func addNote() {
        let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.settings.personalNotes.append(PersonalNote(text: text, category: newCategory))
        newNote = ""
    }
}

/// Chooses between Apple Intelligence and an open model that runs on this Mac.
struct ModelChoice: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller

    /// One entry per model: Apple Intelligence, or one of the open models.
    private enum Choice: Hashable {
        case none
        case apple
        case open(String)   // Hugging Face repository
    }

    var body: some View {
        Picker(selection: primary) {
            Text(CleanupEngine.appleIntelligence.title).tag(Choice.apple)
            ForEach(LocalModelOption.all) { option in
                Text("\(option.name) · \(option.size)").tag(Choice.open(option.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("Primary model")
                Text("All run on this Mac. Nothing you say is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
        }

        Picker(selection: fallback) {
            Text("None").tag(Choice.none)
            if store.settings.cleanupEngine == .localModel {
                Text(CleanupEngine.appleIntelligence.title).tag(Choice.apple)
            } else {
                ForEach(LocalModelOption.all) { option in
                    Text("\(option.name) · \(option.size)").tag(Choice.open(option.id))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("Fallback model")
                Text("Used when the primary model is unavailable, declines or changes your meaning.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
        }

        if store.settings.usesLocalModel {
            if let option = LocalModelOption.named(store.settings.localModelID) {
                Text("\(option.name): \(option.note)").font(.caption).foregroundStyle(Brand.muted)
            }
            status
        }
    }

    private var primary: Binding<Choice> {
        Binding {
            store.settings.cleanupEngine == .localModel ? .open(store.settings.localModelID) : .apple
        } set: { choice in
            switch choice {
            case .open(let id):
                store.settings.cleanupEngine = .localModel
                store.settings.localModelID = id
                // The fallback must be the other kind: only one open model runs at a time.
                if store.settings.fallbackEngine == .localModel { store.settings.fallbackEngine = .appleIntelligence }
                controller.prepareLocalModel()
            case .apple, .none:
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
            case .localModel: .open(store.settings.localModelID)
            }
        } set: { choice in
            switch choice {
            case .none: store.settings.fallbackEngine = nil
            case .apple: store.settings.fallbackEngine = .appleIntelligence
            case .open(let id):
                store.settings.fallbackEngine = .localModel
                store.settings.localModelID = id
                controller.prepareLocalModel()
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch controller.localModelState {
        case .notLoaded:
            Button("Download model") { controller.prepareLocalModel() }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                Text("Downloading once from Hugging Face. Apple Intelligence is used until it's ready.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Couldn't load the model: \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Try again") { controller.prepareLocalModel() }
            }
        }
    }
}
