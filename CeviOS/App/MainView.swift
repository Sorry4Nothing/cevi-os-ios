import SwiftUI

/// Main navigation of the signed-in person.
struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PushManager.self) private var push
    @State private var chatList = ChatListModel()
    @State private var selectedTab: MainTab = .programs
    @State private var programPath: [UUID] = []
    @State private var chatPath: [UUID] = []
    @State private var tabOpacity = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum MainTab: Hashable { case programs, chat, profile }
    let profile: Profile

    /// Parents and unit leaders have chats. Admins and leaders without a unit-leader role do not.
    private var hasChat: Bool { !profile.children.isEmpty || profile.isUnitLeader }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Programme", systemImage: "calendar", value: MainTab.programs) {
                ProgramListView(path: $programPath).opacity(tabOpacity)
            }
            if hasChat {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: MainTab.chat) {
                    ChatListView(model: chatList, profile: profile, path: $chatPath).opacity(tabOpacity)
                }
                .badge(chatList.totalUnread)
            }
            Tab("Profil", systemImage: "person.crop.circle", value: MainTab.profile) {
                ProfileView(profile: profile).opacity(tabOpacity)
            }
        }
        // Chat list (and the badge) stay current while the app is in the foreground.
        .task(id: scenePhase) {
            guard hasChat, scenePhase == .active else { return }
            await chatList.poll(client: state.client)
        }
        .task { await push.prepare() }
        .sheet(isPresented: Binding(get: { push.needsExplanation }, set: { push.needsExplanation = $0 })) {
            PushExplanationView()
        }
        .onChange(of: state.pendingTarget, initial: true) { _, target in open(target) }
        // TabView switches without animation; fade the new tab in. Not with "Reduce Motion".
        .onChange(of: selectedTab) {
            guard !reduceMotion else { return }
            tabOpacity = 0
            // Next turn of the run loop, so the 0 is rendered before fading to 1.
            Task { withAnimation(.easeInOut(duration: 0.26)) { tabOpacity = 1 } }
        }
    }

    /// Opens the target of a tapped push.
    private func open(_ target: PushTarget?) {
        guard let target else { return }
        switch target {
        case .chat(let id) where hasChat:
            selectedTab = .chat
            chatPath = [id]
        case .program(let id):
            selectedTab = .programs
            programPath = [id]
        default:
            break
        }
        state.pendingTarget = nil
    }
}
