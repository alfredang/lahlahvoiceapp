import AppKit
import NovaVoiceCore
import ServiceManagement
import SwiftUI

struct MainWindow: View {
    enum Section: String, CaseIterable, Identifiable {
        case dictation = "Dictation", notes = "Notes", dictionary = "Dictionary", snippets = "Snippets"
        case styles = "Styles", aboutYou = "About You", transforms = "Transforms", insights = "Insights"
        case hotkeys = "Hotkeys", settings = "Settings"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .dictation: "mic"
            case .notes: "record.circle"
            case .dictionary: "character.book.closed"
            case .snippets: "text.bubble"
            case .styles: "textformat"
            case .aboutYou: "person.text.rectangle"
            case .transforms: "wand.and.stars"
            case .insights: "chart.bar"
            case .hotkeys: "command"
            case .settings: "gearshape"
            }
        }

        var subtitle: String {
            switch self {
            case .dictation: "Everything you've dictated. It stays on this Mac."
            case .notes: "Record longer thoughts and get a summary with action items."
            case .dictionary: "Names and terms you want spelled your way."
            case .snippets: "Say a short cue and get the full text."
            case .styles: "Your tone follows the app you're writing in."
            case .aboutYou: "Tell LahLah Voice about you, so it understands and writes like you."
            case .transforms: "Rewrite selected text with one key press, using Apple Intelligence."
            case .insights: "How much you've dictated and where."
            case .hotkeys: "Choose the keys and mouse buttons that control LahLah Voice."
            case .settings: "Language, sounds, privacy and startup."
            }
        }
    }

    @State var selection: Section = .dictation

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            page
        }
        .background(Brand.sand)
        .foregroundStyle(Brand.ink)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                NovaMark(size: 26)
                Text("LahLah Voice").font(.title3.weight(.bold)).lineLimit(1).fixedSize()
                Text("Local")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.localText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Brand.localBadge, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            ForEach([Section.dictation, .notes, .dictionary, .snippets, .styles, .aboutYou, .transforms, .insights]) {
                item($0)
            }
            Spacer()
            item(.hotkeys)
            item(.settings)
        }
        .padding(.top, 46)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 236)
    }

    private func item(_ section: Section) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.symbol).frame(width: 20)
                Text(section.rawValue)
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                selection == section ? Color.black.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private var page: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selection.rawValue).font(.system(size: 30, weight: .semibold))
                    Text(selection.subtitle).foregroundStyle(Brand.muted)
                }
                .padding(.horizontal, 36)
                .padding(.top, 34)
                .padding(.bottom, 20)

                Group {
                    switch selection {
                    case .dictation: HomeView().padding(.horizontal, 36)
                    case .notes: NotesView().padding(.horizontal, 20)
                    case .dictionary: DictionaryView().padding(.horizontal, 20)
                    case .snippets: SnippetsView().padding(.horizontal, 20)
                    case .styles: StylesView().padding(.horizontal, 20)
                    case .aboutYou: AboutYouView().padding(.horizontal, 20)
                    case .transforms: TransformsPage().padding(.horizontal, 36)
                    case .insights: InsightsView().padding(.horizontal, 36)
                    case .hotkeys: HotkeysPage().padding(.horizontal, 36)
                    case .settings: SettingsView().padding(.horizontal, 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("")
            .background(Brand.panel)
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .background(Brand.panel)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 16, style: .continuous)
                .strokeBorder(Brand.hairline)
        }
        .padding(.top, 10)
    }
}

struct HomeView: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller
    @State private var search = ""

    private var matches: [DictationRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(store.history.prefix(100)) }
        return store.history.filter {
            $0.final.localizedCaseInsensitiveContains(query)
                || $0.raw.localizedCaseInsensitiveContains(query)
                || ($0.appName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SetupChecklist()
                if search.isEmpty {
                    howTo
                    stats
                    topApps
                }
                history
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click into a text box in WhatsApp, Telegram, ChatGPT, Claude or anywhere else, hold your key, say what you mean, and let go.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 22) {
                keyHint(.pushToTalk, "Dictate")
                keyHint(.handsFree, "Hands-free")
                keyHint(.editSelection, "Edit selection")
                HStack(spacing: 6) {
                    Keycap(text: "Esc")
                    Text("Cancel").font(.caption).foregroundStyle(Brand.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard()
    }

    @ViewBuilder private func keyHint(_ action: HotkeyAction, _ label: String) -> some View {
        if let hotkey = store.settings.hotkeys(for: action).first {
            HStack(spacing: 6) {
                HotkeyCaps(hotkey: hotkey)
                Text(label).font(.caption).foregroundStyle(Brand.muted)
            }
        }
    }

    private var stats: some View {
        let stats = store.stats
        return HStack(spacing: 12) {
            StatTile(value: stats.totalWords.formatted(), label: "Words dictated")
            StatTile(value: stats.wordsPerMinute > 0 ? "\(stats.wordsPerMinute)" : "–", label: "Words per minute")
            StatTile(value: "\(stats.minutesSaved) min", label: "Saved vs typing")
        }
    }

    @ViewBuilder private var topApps: some View {
        let apps = TopApps.ranked(from: store.history).prefix(5)
        if !apps.isEmpty {
            HStack(spacing: 8) {
                Text("Top apps").font(.callout.weight(.medium))
                ForEach(Array(apps), id: \.name) { app in
                    Button {
                        search = app.name
                    } label: {
                        Text("\(app.name) · \(app.words.formatted())")
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                    TextField("Search your dictations", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .brandCard(cornerRadius: 9)
                .frame(maxWidth: 320)
                Spacer()
                if !store.history.isEmpty, search.isEmpty {
                    Button("Clear history") { store.clearHistory() }
                        .buttonStyle(.link)
                }
            }

            VStack(spacing: 0) {
                if store.history.isEmpty {
                    emptyRow("Your dictations appear here.")
                } else if matches.isEmpty {
                    emptyRow("Nothing matches “\(search)”.")
                }
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { Divider().padding(.horizontal, 18) }
                    HistoryRow(record: record)
                }
            }
            .brandCard()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Brand.muted)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum TopApps {
    struct Entry {
        let name: String
        let words: Int
    }

    static func ranked(from history: [DictationRecord]) -> [Entry] {
        var words: [String: Int] = [:]
        for record in history {
            guard let name = record.appName else { continue }
            words[name, default: 0] += record.wordCount
        }
        return words.map { Entry(name: $0.key, words: $0.value) }.sorted { $0.words > $1.words }
    }
}

struct InsightsView: View {
    @Environment(NovaStore.self) private var store

    /// Words per day for the last seven days, oldest first.
    private var lastWeek: [(day: Date, words: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let words = store.history
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.wordCount }
            return (day, words)
        }
    }

    var body: some View {
        let stats = store.stats
        let apps = TopApps.ranked(from: store.history)
        let peak = max(lastWeek.map(\.words).max() ?? 0, 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    StatTile(value: stats.totalWords.formatted(), label: "Words dictated")
                    StatTile(value: stats.dictations.formatted(), label: "Dictations")
                    StatTile(value: stats.wordsPerMinute > 0 ? "\(stats.wordsPerMinute)" : "–", label: "Words per minute")
                    StatTile(value: "\(stats.minutesSaved) min", label: "Saved vs typing")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Last 7 days").font(.headline)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(lastWeek, id: \.day) { entry in
                            VStack(spacing: 4) {
                                Text(entry.words > 0 ? entry.words.formatted() : "")
                                    .font(.caption2)
                                    .foregroundStyle(Brand.muted)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(entry.words > 0 ? Brand.ember : Color.black.opacity(0.07))
                                    .frame(height: max(4, 110 * CGFloat(entry.words) / CGFloat(peak)))
                                Text(entry.day.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2)
                                    .foregroundStyle(Brand.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 150, alignment: .bottom)
                    .accessibilityElement(children: .combine)
                }
                .padding(16)
                .brandCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where you dictate").font(.headline)
                    if apps.isEmpty {
                        Text("Your most-used apps appear here.").foregroundStyle(Brand.muted)
                    }
                    ForEach(apps, id: \.name) { app in
                        LabeledContent(app.name, value: "\(app.words.formatted()) words")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .brandCard()
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Brand.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(cornerRadius: 12)
    }
}

/// One row of the history table: when on the left, what you said on the right.
struct HistoryRow: View {
    let record: DictationRecord
    @Environment(NovaStore.self) private var store
    @State private var showRaw = false
    @State private var isHovering = false

    private var when: String {
        let date = record.date.formatted(.dateTime.month(.abbreviated).day())
        return "\(date) · \(record.date.formatted(date: .omitted, time: .shortened))"
    }

    private var details: String {
        let seconds = Int(record.durationSeconds.rounded())
        let length = seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min"
        return [length, record.appName].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(when).font(.callout)
                Text(details).font(.caption).lineLimit(1)
            }
            .foregroundStyle(Brand.muted)
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.final).textSelection(.enabled)
                if showRaw {
                    Text("You said: \(record.raw)")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    if record.usedAppleIntelligence {
                        Label("Apple Intelligence", systemImage: "sparkles").foregroundStyle(Brand.muted)
                    }
                    Spacer()
                    Button(showRaw ? "Hide original" : "Show original") { showRaw.toggle() }
                    Button("Copy") { TextInserter.putOnClipboard(record.final) }
                    Button("Delete") { store.deleteHistory(record) }
                }
                .buttonStyle(.link)
                .font(.caption)
                .opacity(isHovering || showRaw ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// Shows only what still needs doing, and disappears when everything is ready.
struct SetupChecklist: View {
    @Environment(DictationController.self) private var controller
    @State private var micGranted = MicrophoneAccess.isGranted
    @State private var axGranted = TextInserter.isTrusted
    @State private var intelligence = AppleIntelligenceEditor.status
    @State private var fnConflict = false
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !micGranted || !axGranted || intelligence != .available || fnConflict {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Finish setting up").font(.headline)
                    if !micGranted {
                        step(
                            "Microphone", "So LahLah Voice can hear you.", action: "Allow",
                            run: {
                                Task {
                                    if MicrophoneAccess.isDenied {
                                        openPrivacy("Privacy_Microphone")
                                    } else {
                                        micGranted = await MicrophoneAccess.request()
                                    }
                                }
                            })
                    }
                    if !axGranted {
                        step(
                            "Accessibility", "So your hotkey works everywhere and text can be pasted into any app.",
                            action: "Open Settings",
                            run: {
                                TextInserter.promptForAccess()
                                TextInserter.openAccessibilitySettings()
                            })
                    }
                    if fnConflict {
                        step(
                            "Fn key", "Pressing 🌐 also opens “\(FnKeySetting.current.title)”, which takes your text. In Keyboard settings, set “Press 🌐 key to” to Do Nothing.",
                            action: "Open Settings", run: FnKeySetting.openKeyboardSettings)
                    }
                    if intelligence != .available {
                        step(
                            intelligence.title, intelligence.detail, action: "Open Settings",
                            run: {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            })
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.ember.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onReceive(timer) { _ in
            micGranted = MicrophoneAccess.isGranted
            intelligence = AppleIntelligenceEditor.status
            fnConflict = controller.fnKeyHasSystemAction
            let granted = TextInserter.isTrusted
            if granted, !axGranted { controller.startHotkeys() }
            axGranted = granted
        }
    }

    private func step(_ title: String, _ detail: String, action: String, run: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action, action: run)
        }
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct StylesView: View {
    @Environment(NovaStore.self) private var store

    var body: some View {
        Form {
            Section {
                ForEach(AppCategory.allCases) { category in
                    Picker(selection: binding(for: category)) {
                        ForEach(WritingStyle.allCases) { Text($0.title).tag($0) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.title)
                            Text(category.examples).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Your tone follows the app you're in")
            } footer: {
                Text("Tone changes use Apple Intelligence. Without it, LahLah Voice still cleans up your text.")
            }
            Section("What each style does") {
                ForEach(WritingStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(style.title).fontWeight(.medium)
                        Text(style.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func binding(for category: AppCategory) -> Binding<WritingStyle> {
        Binding(
            get: { store.settings.categoryStyles[category.rawValue] ?? category.defaultStyle },
            set: { store.settings.categoryStyles[category.rawValue] = $0 })
    }
}

struct SettingsView: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller
    @State private var locales: [Locale] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Dictation") {
                Picker("Language", selection: $store.settings.localeIdentifier) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(SpeechEngine.displayName(for: locale)).tag(locale.identifier)
                    }
                }
                Toggle("Understand what I meant, not just what I said", isOn: $store.settings.useAppleIntelligence)
                if store.settings.useAppleIntelligence {
                    ModelChoice()
                }
                Toggle("Play a sound when dictation starts and stops", isOn: $store.settings.playSounds)
                Toggle("Mute speakers while dictating", isOn: $store.settings.muteWhileDictating)
                Toggle(isOn: $store.settings.pressEnterCommand) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Press Return when I end with “press enter”")
                        Text("In most chat apps this sends your message straight away.")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
            Section("API") {
                APISettings()
            }
            Section("Sending") {
                Toggle(isOn: $store.settings.sendInAgentApps) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Send straight away in Wiki LLM and Planner")
                        Text("Your words go to the agent and it answers, like a voice message.")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                Toggle(isOn: $store.settings.lahlahVideoCommands) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LahLah Video commands")
                        Text("In LahLah Video, or when you start with “Video,”, your words run as edits like “split here” instead of being typed.")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                Toggle(isOn: $store.settings.spaceToSend) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Space finishes and sends while listening hands-free")
                        Text("Or click Send on the bar. Either way Return is pressed after your text.")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
            Section("Privacy") {
                Toggle(isOn: $store.settings.learnCorrections) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Learn words I correct")
                        Text("Rereads the text box for a minute after pasting. A word you fix is added to your dictionary. Stays on this Mac.")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                Toggle("Keep dictation history on this Mac", isOn: $store.settings.keepHistory)
                Toggle(isOn: $store.settings.useTextBoxContext) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Spell names from the text box I'm writing in")
                        Text("Picks out capitalised names from that box when you start dictating. They stay on this Mac, and password fields are never read.")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }
                Text("Speech recognition and editing run on this Mac. LahLah Voice has no account or server, and your voice and text are never sent to us.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Open LahLah Voice at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        if enable {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            Section("About") {
                LabeledContent("Developer", value: "Tertiary Infotech Academy Pte Ltd")
                if let privacy = URL(string: "https://www.tertiaryinfotech.com/privacy") {
                    Link("Privacy policy", destination: privacy)
                }
                if let terms = URL(string: "https://www.tertiaryinfotech.com/terms") {
                    Link("Terms of service", destination: terms)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            locales = await SpeechEngine.supportedLocales()
            // If the saved language isn't an exact match, select the closest one so the picker isn't blank.
            let saved = Locale(identifier: store.settings.localeIdentifier)
            if !locales.contains(where: { $0.identifier == saved.identifier }),
                let best = await SpeechEngine.bestLocale(for: saved)
            {
                store.settings.localeIdentifier = best.identifier
            }
        }
    }
}

/// Settings › API: the local control API for scripts, Claude and LahLah Video.
struct APISettings: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller
    @State private var showKey = false

    var body: some View {
        @Bindable var store = store
        let control = controller.control
        Toggle(isOn: $store.settings.apiEnabled) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Allow API control")
                Text("Scripts on this Mac can start and stop dictation and send commands to LahLah Video. Listens on 127.0.0.1 only.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
        }
        .onChange(of: store.settings.apiEnabled) { control.publish() }
        LabeledContent("API key") {
            HStack {
                Text(showKey ? control.key : String(control.key.prefix(9)) + String(repeating: "•", count: 20))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(control.key, forType: .string)
                }
                Button("Regenerate", role: .destructive) { control.regenerateKey() }
            }
        }
        LabeledContent("Base URL") {
            Text(control.baseURL).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
        Link("API reference", destination: URL(string: "https://github.com/alfredang/lahlahvoiceapp/blob/main/docs/API.md")!)
    }
}
