import NovaVoiceCore
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(NovaStore.self) private var store
    @Environment(VoiceSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var showSetup = false
    @State private var keyboardReady = SessionBridge.shared.keyboardHasRunWithFullAccess
    @State private var justCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !keyboardReady && !DemoMode.isActive { setupCard }
                sessionCard
                tryItCard
                statsRow
                recent
            }
            .padding()
        }
        .background(Brand.sand)
        .navigationTitle("LahLah Voice")
        .sheet(isPresented: $showSetup) {
            NavigationStack { SetupView() }
        }
        .onChange(of: scenePhase) {
            keyboardReady = SessionBridge.shared.keyboardHasRunWithFullAccess
        }
        .onAppear {
            session.onLocalResult = { text in
                draft += (draft.isEmpty ? "" : " ") + text
            }
        }
    }

    private var setupCard: some View {
        Button {
            showSetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.ellipsis").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add the LahLah Voice keyboard").font(.headline)
                    Text("Use your voice in WhatsApp, Telegram, ChatGPT and any other app.")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .background(Brand.ember.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NovaMark(size: 28)
                Text(session.isOpen ? "Voice session open" : "Ready when you are")
                    .font(.headline)
            }
            Text(session.isOpen
                ? "Go to any app and tap Speak on the LahLah Voice keyboard. The session closes by itself after \(store.settings.sessionMinutes) idle minutes."
                : "Start a session, then tap Speak on the LahLah Voice keyboard in any app.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    if session.isOpen {
                        await session.endSession()
                    } else {
                        try? await session.startSession()
                    }
                }
            } label: {
                Label(session.isOpen ? "End session" : "Start voice session",
                      systemImage: session.isOpen ? "stop.fill" : "mic.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isOpen ? Brand.ember : Brand.ink)

            if let failure = session.lastFailure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(cornerRadius: 16)
    }

    private var tryItCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try it here").font(.headline)
            TextField("Tap the button below, then say something like “um, let's meet Tuesday, no wait, Wednesday”.",
                      text: $draft, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
                .writingToolsBehavior(.complete)

            if session.state == .listening, !session.partial.isEmpty {
                Text(session.partial).font(.footnote).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    if session.state == .listening {
                        session.endDictation()
                    } else if session.state != .working {
                        Task { await session.beginLocalDictation() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if session.state == .listening {
                            WaveformView(level: session.level)
                            Text("Done")
                        } else if session.state == .working {
                            Image(systemName: "ellipsis")
                            Text("Writing…")
                        } else {
                            Image(systemName: "mic.fill")
                            Text("Speak")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.state == .listening ? Brand.ember : Brand.ink)

                if !draft.isEmpty {
                    Button(justCopied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = draft
                        justCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            justCopied = false
                        }
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: draft) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Share text")
                }
            }
        }
        .padding()
        .brandCard(cornerRadius: 16)
    }

    private var statsRow: some View {
        let stats = store.stats
        return HStack(spacing: 10) {
            statTile(stats.totalWords.formatted(), "Words")
            statTile(stats.wordsPerMinute > 0 ? "\(stats.wordsPerMinute)" : "–", "Words a minute")
            statTile("\(stats.minutesSaved) min", "Time saved")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(cornerRadius: 12)
    }

    @ViewBuilder private var recent: some View {
        if !store.history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent").font(.headline)
                ForEach(store.history.prefix(30)) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.final).textSelection(.enabled)
                        Text("You said: \(record.raw)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack {
                            Text(record.date.formatted(date: .omitted, time: .shortened))
                            if record.usedAppleIntelligence {
                                Label("Apple Intelligence", systemImage: "sparkles")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandCard(cornerRadius: 12)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = record.final
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.deleteHistory(record)
                        }
                    }
                }
            }
        }
    }
}

/// Everything needed to get going, with a live preview of the keyboard.
struct SetupView: View {
    @Environment(NovaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardReady = SessionBridge.shared.keyboardHasRunWithFullAccess
    @State private var micGranted = MicrophoneAccess.isGranted
    @State private var modelReady = false
    @State private var modelProgress: Double?
    @State private var previewModel = KeyboardModel()

    private var intelligence: IntelligenceStatus { AppleIntelligenceEditor.status }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .task {
                    // Screenshots show the keyboard, which sits at the bottom of this screen.
                    guard DemoMode.current?.tab == .setup else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo("keyboard", anchor: .bottom)
                }
        }
    }

    private var list: some View {
        List {
            Section {
                row(done: micGranted, title: "Allow the microphone", detail: "So LahLah Voice can hear you while you dictate.") {
                    Button("Allow") {
                        Task {
                            if MicrophoneAccess.isDenied {
                                openSettings()
                            } else {
                                micGranted = await MicrophoneAccess.request()
                            }
                        }
                    }
                }
                row(done: modelReady, title: "Download speech recognition", detail: "A one-time download from Apple. Recognition then runs on this iPhone.") {
                    if let modelProgress {
                        ProgressView(value: modelProgress).frame(width: 60)
                    } else {
                        Button("Get") { download() }
                    }
                }
                row(done: keyboardReady, title: "Add the keyboard", detail: "Settings › General › Keyboard › Keyboards › Add New Keyboard › LahLah Voice. Then tap LahLah Voice and turn on Allow Full Access.") {
                    Button("Settings") { openSettings() }
                }
                row(done: intelligence == .available, title: intelligence.title, detail: intelligence.detail) {
                    EmptyView()
                }
            } header: {
                Text("Set up")
            } footer: {
                Text("Full Access only lets the keyboard reach the LahLah Voice app on this iPhone. Your speech and text aren't sent anywhere, and typing works without it.")
            }

            Section("How it works") {
                Label("Start a session here, from Control Center, with the Action button, or by asking Siri.", systemImage: "1.circle")
                Label("Go to WhatsApp, Telegram, ChatGPT or any other app and switch to the LahLah Voice keyboard.", systemImage: "2.circle")
                Label("Tap Speak, talk naturally, and tap again. Your text appears, without the ums and false starts.", systemImage: "3.circle")
            }

            Section("Your keyboard") {
                KeyboardView(model: previewModel)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.gray.opacity(0.18))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id("keyboard")
            }
        }
        .brandListBackground()
        .navigationTitle("Set up LahLah Voice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
        .task { await refresh() }
        .onChange(of: scenePhase) { Task { await refresh() } }
    }

    private func row(done: Bool, title: String, detail: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { action().buttonStyle(.bordered) }
        }
    }

    private func refresh() async {
        keyboardReady = SessionBridge.shared.keyboardHasRunWithFullAccess
        micGranted = MicrophoneAccess.isGranted
        let requested = Locale(identifier: store.settings.localeIdentifier)
        if let locale = await SpeechEngine.bestLocale(for: requested) {
            modelReady = await SpeechEngine.isInstalled(locale)
        }
    }

    private func download() {
        modelProgress = 0
        Task {
            let requested = Locale(identifier: store.settings.localeIdentifier)
            let locale = await SpeechEngine.bestLocale(for: requested) ?? requested
            try? await SpeechEngine.ensureInstalled(locale) { value in
                Task { @MainActor in modelProgress = value }
            }
            modelProgress = nil
            await refresh()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
