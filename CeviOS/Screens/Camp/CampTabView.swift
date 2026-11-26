import SwiftUI

/// The camp view: tab bar with the destinations that exist. Start (L2/L3 with «Heute» L4), Aufgaben (L5, for leads), Anwesenheit (L26, for the team) and Pinnwand (L16) are built. «Mehr» opens the sheet (L37) and does not keep the selection.
struct CampTabView: View {
    let profile: Profile
    let chatList: ChatListModel
    let hasChat: Bool
    @Binding var chatPath: [UUID]
    @Environment(ActiveCamp.self) private var active
    @State private var selected: CampTab = .start
    @State private var showsMore = false

    enum CampTab: Hashable { case start, tasks, attendance, notices, chat, more }

    var body: some View {
        TabView(selection: $selected) {
            Tab("Start", systemImage: "house", value: CampTab.start) {
                CampStartView(profile: profile) { selected = .tasks }
            }
            if CampTaskRights(role: active.role, readOnly: false, personId: nil).seesTaskList {
                Tab("Aufgaben", systemImage: "checkmark.circle", value: CampTab.tasks) {
                    CampTasksView(profile: profile) { selected = .start }
                }
            }
            // The team has no task list; its fast way to the own presence is a tab (the leads find it in «Mehr»).
            if active.role == .team {
                Tab("Anwesenheit", systemImage: "checklist.checked", value: CampTab.attendance) {
                    NavigationStack { CampAttendanceView(profile: profile) }
                }
            }
            Tab("Pinnwand", systemImage: "megaphone", value: CampTab.notices) { CampNoticesView() }
            if hasChat {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: CampTab.chat) {
                    ChatListView(model: chatList, profile: profile, path: $chatPath)
                }
                .badge(chatList.totalUnread)
            }
            Tab("Mehr", systemImage: "ellipsis", value: CampTab.more) { Color.clear }
        }
        // Another camp: every tab starts anew with its data.
        .id(active.camp?.id)
        .onChange(of: selected) { old, new in
            guard new == .more else { return }
            selected = old
            showsMore = true
        }
        // A tapped push: the Pinnwand is a tab, the other targets sit in the «Mehr» sheet.
        .onChange(of: active.destination, initial: true) { _, destination in
            if destination == .notices { selected = .notices; active.destination = nil }
            else if destination == .tasks {
                if CampTaskRights(role: active.role, readOnly: false, personId: nil).seesTaskList { selected = .tasks }
                active.destination = nil
            }
            else if destination == .attendance, active.role == .team { selected = .attendance; active.destination = nil }
            else if destination != nil { showsMore = true }
        }
        .sheet(isPresented: $showsMore) {
            CampMoreSheet(profile: profile) { active.showsChooser = true }
        }
    }
}
