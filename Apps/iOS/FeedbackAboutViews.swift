import SwiftUI
import UIKit

struct FeedbackView: View {
    private let whatsAppNumber = "6588666375"
    @State private var title = ""
    @State private var message = ""

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Feedback").font(.largeTitle.bold())
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("Your message…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $message)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button(action: send) {
                    Label("Send via WhatsApp", systemImage: "paperplane.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
            .padding(22)
        }
    }

    private func send() {
        var body = ""
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { body += "*\(t)*\n" }
        body += m
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(whatsAppNumber)"
        components.queryItems = [URLQueryItem(name: "text", value: body)]
        if let url = components.url { UIApplication.shared.open(url) }
    }
}

struct AboutView: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("About").font(.largeTitle.bold())

                card {
                    HStack(spacing: 10) {
                        NovaMark(size: 30)
                        Text("LahLah Voice").font(.title3.bold())
                    }
                    Text("Say what you mean, in any app. LahLah Voice removes the ums, follows your corrections and writes what you intended. Recognition and editing run on your device with Apple Intelligence.")
                        .font(.subheadline)
                }

                card {
                    Text("Your privacy").font(.headline)
                    Text("No account, no servers, no tracking. Your voice and text stay on this iPhone.")
                        .font(.subheadline)
                    Link("Privacy policy", destination: AppLinks.privacy)
                        .font(.subheadline)
                    Link("Terms of service", destination: AppLinks.terms)
                        .font(.subheadline)
                }

                card {
                    Text("Developer").font(.headline)
                    Text("Tertiary Infotech Academy Pte Ltd").font(.subheadline)
                    Link("tertiaryinfotech.com", destination: AppLinks.developer)
                        .font(.subheadline)
                    Link("Support", destination: AppLinks.support)
                        .font(.subheadline)
                }

                card {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .padding(22)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard()
    }
}

enum AppLinks {
    static let privacy = URL(string: "https://www.tertiaryinfotech.com/privacy")!
    static let terms = URL(string: "https://www.tertiaryinfotech.com/terms")!
    static let support = URL(string: "https://alfredang.github.io/lahlahvoice/support.html")!
    static let developer = URL(string: "https://www.tertiaryinfotech.com")!
}
