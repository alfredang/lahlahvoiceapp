import NovaVoiceCore
import SwiftUI

struct DictionaryView: View {
    @Environment(NovaStore.self) private var store
    @State private var term = ""
    @State private var soundsLike = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                TextField("Word or name", text: $term)
                TextField("Sounds like (optional, comma separated)", text: $soundsLike)
                Button("Add to dictionary", systemImage: "plus") { add() }
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("LahLah Voice favours these spellings and passes them to Apple's speech recogniser.")
            }

            Section("Your words") {
                if store.dictionary.isEmpty {
                    Text("Add names, brands and jargon that get misheard.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.dictionary) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.term).fontWeight(.medium)
                        if !entry.soundsLike.isEmpty {
                            Text("Heard as: " + entry.soundsLike.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.dictionary.removeAll { $0.id == entry.id }
                        }
                    }
                }
                .onDelete { store.dictionary.remove(atOffsets: $0) }
            }
        }
        .formStyle(.grouped)
        .brandListBackground()
        .navigationTitle("Dictionary")
    }

    private func add() {
        let forms = soundsLike.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        store.dictionary.append(
            DictionaryEntry(term: term.trimmingCharacters(in: .whitespaces), soundsLike: forms))
        term = ""
        soundsLike = ""
    }
}

struct SnippetsView: View {
    @Environment(NovaStore.self) private var store
    @State private var cue = ""
    @State private var expansion = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                TextField("When I say…", text: $cue)
                TextField("Type this", text: $expansion, axis: .vertical)
                    .lineLimit(2...6)
                Button("Add snippet", systemImage: "plus") {
                    store.snippets.append(
                        Snippet(
                            cue: cue.trimmingCharacters(in: .whitespaces),
                            expansion: expansion))
                    cue = ""
                    expansion = ""
                }
                .disabled(cue.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            } footer: {
                Text("Say the cue and LahLah Voice types the saved text exactly, for links, addresses and common replies.")
            }

            Section("Your snippets") {
                if store.snippets.isEmpty {
                    Text("Try “my calendar link” or “my work address”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(snippet.cue)”").fontWeight(.medium)
                        Text(snippet.expansion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.snippets.removeAll { $0.id == snippet.id }
                        }
                    }
                }
                .onDelete { store.snippets.remove(atOffsets: $0) }
            }
        }
        .formStyle(.grouped)
        .brandListBackground()
        .navigationTitle("Snippets")
    }
}
