import Foundation
import Testing

@testable import NovaVoiceCore

@Suite struct LahLahVideoCommandsTests {
    private let video = LahLahVideoCommands.bundleID

    @Test func wakeWordsWorkFromAnyApp() {
        #expect(LahLahVideoCommands.command(from: "Video, split here.", frontmostBundleID: "com.apple.Safari") == "split here")
        #expect(LahLahVideoCommands.command(from: "LahLah Video, add crossfade", frontmostBundleID: nil) == "add crossfade")
        #expect(LahLahVideoCommands.command(from: "lah lah video export for TikTok", frontmostBundleID: nil) == "export for TikTok")
        #expect(LahLahVideoCommands.command(from: "Video: split at 3 seconds", frontmostBundleID: nil) == "split at 3 seconds")
    }

    @Test func plainSentencesAreStillTyped() {
        #expect(LahLahVideoCommands.command(from: "Video calls are tiring", frontmostBundleID: "com.apple.mail") == nil)
        #expect(LahLahVideoCommands.command(from: "Split the bill with Ah Hock", frontmostBundleID: "com.apple.MobileSMS") == nil)
        #expect(LahLahVideoCommands.command(from: "Video,", frontmostBundleID: nil) == nil)
    }

    @Test func everythingGoesToLahLahVideoWhenItIsInFront() {
        #expect(LahLahVideoCommands.command(from: "Split at 3 seconds.", frontmostBundleID: video) == "Split at 3 seconds")
        #expect(LahLahVideoCommands.command(from: "Video, undo", frontmostBundleID: video) == "undo")
    }

    @Test func buildsTheDeepLink() {
        let url = LahLahVideoCommands.url(for: "add text 'Save first' at 2 seconds")
        #expect(url?.scheme == "lahlahvideo")
        #expect(url?.host == "command")
        let text = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        #expect(text == "add text 'Save first' at 2 seconds")
    }

    @Test func oldSettingsTurnTheFeatureOn() throws {
        let settings = try JSONDecoder().decode(NovaSettings.self, from: Data("{}".utf8))
        #expect(settings.lahlahVideoCommands)
    }
}
