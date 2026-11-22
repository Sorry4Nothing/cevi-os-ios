import SwiftUI

/// The camp view: tab bar with the destinations that exist. Start, Aufgaben and Pinnwand of the design follow with their
/// slices; «Mehr» opens the sheet (L37) and does not keep the selection.
struct CampTabView: View {
    let profile: Profile
    let chatList: ChatListModel
    let hasChat: Bool
    @Binding var chatPath: [UUID]
    @Environment(ActiveCamp.self) private var active
    @State private var selected: CampTab = .start
    @State private var showsMore = false

    enum CampTab: Hashable { case start, chat, more }

    var body: some View {
        TabView(selection: $selected) {
            Tab("Start", systemImage: "house", value: CampTab.start) { CampStartView() }
            if hasChat {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: CampTab.chat) {
                    ChatListView(model: chatList, profile: profile, path: $chatPath)
                }
                .badge(chatList.totalUnread)
            }
            Tab("Mehr", systemImage: "ellipsis", value: CampTab.more) { Color.clear }
        }
        .onChange(of: selected) { old, new in
            guard new == .more else { return }
            selected = old
            showsMore = true
        }
        .sheet(isPresented: $showsMore) {
            CampMoreSheet(profile: profile) { active.showsChooser = true }
        }
    }
}

/// Landing of the camp view until the real start (A1) exists: shows the camp itself and the cross-cutting banners.
struct CampStartView: View {
    @Environment(ActiveCamp.self) private var active
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    if active.waitingCount > 0 {
                        CampQueueBanner(waiting: active.waitingCount, offline: active.isOffline) {
                            Task { await active.sendWaiting() }
                        }
                    }
                    if active.isReadOnly { CampClosedBanner() }
                    if let camp = active.camp, let role = active.role {
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Text(active.isReadOnly ? "Das Lager ist vorbei" : camp.title).font(.title(.cardTitle))
                            Text(CampFormat.dates(from: camp.from, to: camp.to) + (camp.place.map { ", \($0)" } ?? ""))
                                .foregroundStyle(Color.ceviOnSurfaceVariant)
                            Text("Deine Rolle: \(CampRoleText.name(role))").foregroundStyle(Color.ceviOnSurfaceVariant)
                        }
                        .foregroundStyle(Color.ceviOnSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ceviCard()
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .ceviScreenBackground()
            .navigationTitle(active.title)
            .navigationBarTitleDisplayMode(.inline)
            .campSwitcher()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await active.refreshQueue()
        }
    }
}
