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
    @State private var campList = CampListModel()
    @State private var activeCamp = ActiveCamp()
    /// The camp of a tapped push could not be opened.
    @State private var pushState: CampScreenState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum MainTab: Hashable { case programs, chat, profile }
    let profile: Profile

    /// Parents and unit leaders have chats. Admins and leaders without a unit-leader role do not.
    private var hasChat: Bool { !profile.children.isEmpty || profile.isUnitLeader }

    var body: some View {
        Group {
            if activeCamp.isOpen {
                CampTabView(profile: profile, chatList: chatList, hasChat: hasChat, chatPath: $chatPath)
            } else {
                programTabs
            }
        }
        .environment(campList)
        .environment(activeCamp)
        // The switcher shows only for members of a camp; a failed load leaves the app as it was.
        .task { await campList.load(client: state.client) }
        .sheet(isPresented: Binding(get: { activeCamp.showsChooser }, set: { activeCamp.showsChooser = $0 })) {
            NavigationStack {
                CampChooserView(model: campList, retry: { Task { await campList.load(client: state.client) } }) { entry in
                    activeCamp.open(entry, client: state.client)
                    activeCamp.showsChooser = false
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schliessen", systemImage: "xmark") { activeCamp.showsChooser = false }
                    }
                }
            }
            .task { await campList.load(client: state.client) }
        }
        .sheet(item: $pushState) { pushed in
            CampStateView(state: pushed, back: .toPrograms { pushState = nil }, signIn: { pushState = nil }, retry: { pushState = nil })
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
    }

    private var programTabs: some View {
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
            activeCamp.leave()
            selectedTab = .chat
            chatPath = [id]
        case .program(let id):
            activeCamp.leave()
            selectedTab = .programs
            programPath = [id]
        case .chats where hasChat:
            activeCamp.leave()
            selectedTab = .chat
            chatPath = []
        case .campArea(let area, let id):
            Task { pushState = await CampRouter.open(area: area, campId: id, client: state.client, list: campList, active: activeCamp) }
        case .roomRequests:
            activeCamp.leave()
            selectedTab = .profile
            state.showsRoomDecisions = true
        case .camp(let type, let id):
            Task { pushState = await CampRouter.open(type: type, objectId: id, client: state.client, list: campList, active: activeCamp) }
        default:
            break
        }
        state.pendingTarget = nil
    }
}
