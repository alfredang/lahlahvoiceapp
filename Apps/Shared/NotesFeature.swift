import NovaVoiceCore
import Observation
import SwiftUI

/// Records a long voice note with live on-device transcription, then has Apple Intelligence
/// write a title, summary and action items.
@MainActor
@Observable
final class NoteRecorder {
    enum Phase: Equatable {
        case idle, starting, recording, summarising
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var level: Float = 0

    private let capture = AudioCapture()
    private let speech = SpeechEngine()
    private var startedAt = Date()

    func start(store: NovaStore) async {
        phase = .starting
        transcript = ""
        do {
            guard await MicrophoneAccess.request() else {
                phase = .failed("LahLah Voice needs microphone access to record notes.")
                return
            }
            let locale = await chosenLocale(store)
            speech.onPartial = { [weak self] text in
                Task { @MainActor in self?.transcript = text }
            }
            capture.onBuffer = { [speech] in speech.append($0) }
            capture.onLevel = { [weak self] value in
                Task { @MainActor in self?.level = value }
            }
            speech.beginBuffering()
            try capture.start()
            capture.isForwarding = true
            try await speech.start(locale: locale, vocabulary: store.dictionary.map(\.term))
            startedAt = Date()
            phase = .recording
        } catch {
            capture.stop()
            await speech.cancel()
            phase = .failed(error.localizedDescription)
        }
    }

    func stop(store: NovaStore) async {
        guard phase == .recording else { return }
        capture.stop()
        phase = .summarising
        let duration = Date().timeIntervalSince(startedAt)
        let text = await speech.finish()
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        let locale = await chosenLocale(store)
        var note = VoiceNote(title: "Voice note", transcript: text, durationSeconds: duration)
        if store.settings.useAppleIntelligence,
            let summary = await AppleIntelligenceEditor().summarise(text, locale: locale)
        {
            note.title = summary.title
            var body = summary.summary
            if !summary.actionItems.isEmpty {
                body += "\n\nAction items:\n" + summary.actionItems.map { "• \($0)" }.joined(separator: "\n")
            }
            note.summary = body
        }
        store.notes.insert(note, at: 0)
        phase = .idle
        transcript = ""
    }

    private func chosenLocale(_ store: NovaStore) async -> Locale {
        let requested = Locale(identifier: store.settings.localeIdentifier)
        return await SpeechEngine.bestLocale(for: requested) ?? requested
    }
}

struct NotesView: View {
    @Environment(NovaStore.self) private var store
    @State private var recorder = NoteRecorder()

    var body: some View {
        Form {
            Section {
                recordRow
                if !recorder.transcript.isEmpty {
                    Text(recorder.transcript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if case .failed(let message) = recorder.phase {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Uses your microphone and stays on this device. Get permission from anyone you record.")
            }

            Section("Notes") {
                if store.notes.isEmpty {
                    Text("Your voice notes and summaries appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.notes) { note in
                    NavigationLink(value: note) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).fontWeight(.medium)
                            Text(note.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.notes.removeAll { $0.id == note.id }
                        }
                    }
                }
                .onDelete { store.notes.remove(atOffsets: $0) }
            }
        }
        .formStyle(.grouped)
        .brandListBackground()
        .navigationTitle("Notes")
        .navigationDestination(for: VoiceNote.self) { NoteDetailView(note: $0) }
    }

    @ViewBuilder private var recordRow: some View {
        switch recorder.phase {
        case .recording:
            Button {
                Task { await recorder.stop(store: store) }
            } label: {
                HStack {
                    WaveformView(level: recorder.level, color: Brand.ember)
                    Text("Stop and summarise").fontWeight(.medium)
                }
            }
        case .starting:
            Label("Getting ready…", systemImage: "hourglass")
        case .summarising:
            Label("Writing your summary…", systemImage: "sparkles")
        case .idle, .failed:
            Button("Record a note", systemImage: "record.circle") {
                Task { await recorder.start(store: store) }
            }
        }
    }
}

struct NoteDetailView: View {
    let note: VoiceNote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note.date.formatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let summary = note.summary {
                    Text("Summary").font(.headline)
                    Text(summary).textSelection(.enabled)
                }
                Text("Transcript").font(.headline)
                Text(note.transcript).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(note.title)
        .toolbar {
            ShareLink(item: (note.summary.map { $0 + "\n\n" } ?? "") + note.transcript)
        }
    }
}
