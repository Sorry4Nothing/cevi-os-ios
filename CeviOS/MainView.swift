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

    enum MainTab: Hashable { case programs, chat, attendance, profile }
    let profile: Profile

    private var attendanceUnits: [UnitSummary] {
        LeadershipPermissions(profile: profile).attendanceUnits(from: profile.units)
    }

    /// Parents and unit leaders have chats. Admins and leaders without a unit-leader role do not.
    private var hasChat: Bool { !profile.children.isEmpty || profile.isUnitLeader }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Programme", systemImage: "calendar", value: MainTab.programs) {
                ProgramListView(path: $programPath)
            }
            if hasChat {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: MainTab.chat) {
                    ChatListView(model: chatList, profile: profile, path: $chatPath)
                }
                .badge(chatList.totalUnread)
            }
            if !attendanceUnits.isEmpty {
                Tab("Anwesenheit", systemImage: "checklist", value: MainTab.attendance) {
                    AttendanceListView(units: attendanceUnits)
                }
            }
            Tab("Profil", systemImage: "person.crop.circle", value: MainTab.profile) {
                ProfileView(profile: profile)
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
