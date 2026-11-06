import NovaVoiceCore
import SwiftUI

struct MainTabView: View {
    enum Tab: String { case home, notes, personalize, feedback, about, setup }

    @State var initialTab: Tab

    var body: some View {
        TabView(selection: $initialTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "waveform") }
                .tag(Tab.home)
            NavigationStack { NotesView() }
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)
            NavigationStack { PersonalizeView() }
                .tabItem { Label("Personalize", systemImage: "slider.horizontal.3") }
                .tag(Tab.personalize)
            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.feedback)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(Tab.about)
        }
        .sheet(isPresented: Binding(
            get: { initialTab == .setup },
            set: { if !$0 { initialTab = .home } }
        )) {
            NavigationStack { SetupView() }
        }
    }
}
