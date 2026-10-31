import SwiftUI

/// Main navigation of the signed-in person. Chat and profile tabs follow with their issues.
struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var chatList = ChatListModel()
    let profile: Profile

    private var attendanceUnits: [UnitSummary] {
        LeadershipPermissions(profile: profile).attendanceUnits(from: profile.units)
    }

    /// Parents and unit leaders have chats. Admins and leaders without a unit-leader role do not.
    private var hasChat: Bool { !profile.children.isEmpty || profile.isUnitLeader }

    var body: some View {
        TabView {
            Tab("Programme", systemImage: "calendar") {
                ProgramListView()
            }
            if hasChat {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                    ChatListView(model: chatList, profile: profile)
                }
                .badge(chatList.totalUnread)
            }
            if !attendanceUnits.isEmpty {
                Tab("Anwesenheit", systemImage: "checklist") {
                    AttendanceListView(units: attendanceUnits)
                }
            }
            Tab("Profil", systemImage: "person.crop.circle") {
                VStack(spacing: 16) {
                    Text("Hallo \(profile.ceviName ?? profile.name)")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Button("Abmelden", role: .destructive) {
                        Task { await state.signOut() }
                    }
                    .frame(minHeight: 44)
                }
                .padding()
            }
        }
        // Chat list (and the badge) stay current while the app is in the foreground.
        .task(id: scenePhase) {
            guard hasChat, scenePhase == .active else { return }
            await chatList.poll(client: state.client)
        }
    }
}
