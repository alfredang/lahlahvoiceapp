import AppKit
import NovaVoiceCore
import SwiftUI

@main
struct NovaVoiceMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: NovaStore
    @State private var controller: DictationController

    init() {
        let store = NovaStore()
        let controller = DictationController(store: store)
        _store = State(initialValue: store)
        _controller = State(initialValue: controller)
        controller.activate()
        #if DEBUG
        MacSnapshots.runIfRequested(store: store, controller: controller)
        #endif
    }

    var body: some Scene {
        Window("LahLah Voice", id: "main") {
            MainWindow()
                .environment(store)
                .environment(controller)
                .frame(minWidth: 860, minHeight: 560)
                .tint(Brand.accent)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 700)

        MenuBarExtra {
            MenuBarContent()
                .environment(store)
                .environment(controller)
        } label: {
            Image(systemName: controller.menuBarSymbol)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Dictation lives in the menu bar, so closing the window must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Don't leave the speakers muted if the app quits in the middle of a dictation.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { SystemAudio.restoreOutput() }
    }
}

struct MenuBarContent: View {
    @Environment(NovaStore.self) private var store
    @Environment(DictationController.self) private var controller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.statusLine)
        Divider()
        Button(controller.isActive ? "Stop dictating" : "Start dictating") {
            controller.toggleHandsFree()
        }
        Divider()
        if !store.history.isEmpty {
            Button("Paste last dictation") { controller.pasteLast() }
        }
        Button("Open LahLah Voice") {
            NSApp.activate()
            openWindow(id: "main")
        }
        Divider()
        Button("Quit LahLah Voice") { NSApp.terminate(nil) }
    }
}

#if DEBUG
/// `-NVSnapshot <folder>` renders each main screen to a PNG with sample data, then quits.
/// Capturing the app's real window needs Screen Recording permission, so screens are hosted here.
@MainActor
enum MacSnapshots {
    static func runIfRequested(store: NovaStore, controller: DictationController) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-NVSnapshot"), arguments.count > index + 1 else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        store.seedForScreenshots(
            history: [
                DictationRecord(
                    raw: "um can you send the report by tuesday no wait wednesday",
                    final: "Can you send the report by Wednesday?", appName: "WhatsApp",
                    durationSeconds: 5, usedAppleIntelligence: true),
                DictationRecord(
                    date: Date().addingTimeInterval(-90000),
                    raw: "write a function that parses the csv file and returns the totals",
                    final: "Write a function that parses the CSV file and returns the totals.",
                    appName: "claude.ai", durationSeconds: 4, usedAppleIntelligence: true),
            ],
            notes: [], dictionary: [DictionaryEntry(term: "LahLah Voice")],
            snippets: [Snippet(cue: "my calendar link", expansion: "https://calendar.example.com")])

        let screens: [(String, AnyView)] = [
            ("home", AnyView(MainWindow(selection: .dictation))),
            ("notes", AnyView(MainWindow(selection: .notes))),
            ("dictionary", AnyView(MainWindow(selection: .dictionary))),
            ("transforms", AnyView(MainWindow(selection: .transforms))),
            ("hotkeys", AnyView(MainWindow(selection: .hotkeys))),
            ("insights", AnyView(MainWindow(selection: .insights))),
            ("styles", AnyView(MainWindow(selection: .styles))),
            ("settings", AnyView(MainWindow(selection: .settings))),
            ("hud", AnyView(HUDView(message: "No text box in focus. Your text is on the clipboard: press ⌘V").frame(width: 560, height: 100))),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, screen) in screens {
                let host = NSHostingView(
                    rootView: screen.environment(store).environment(controller).tint(Brand.accent).environment(\.colorScheme, .light))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700), styleMask: [.titled],
                    backing: .buffered, defer: false)
                window.contentView = host
                window.orderBack(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(1.5))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: folder.appending(path: "mac-\(name).png"))
                window.orderOut(nil)
            }
            exit(0)
        }
    }
}
#endif
