import SwiftUI

/// L37: «Mehr» of the camp view. Only entries whose target exists; the others follow with their slices (`docs/lager.md`).
struct CampMoreSheet: View {
    let profile: Profile
    let showAllCamps: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ActiveCamp.self) private var active
    @State private var showsProfile = false
    @State private var path: [CampDestination] = []

    /// Entries whose target exists and that the role may open.
    private var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { showsProfile = true } label: { row("Profil", symbol: "person.crop.circle") }
                }
                Section("Lager") {
                    NavigationLink(value: CampDestination.meetings) { row("Hoecks", symbol: "calendar") }
                    NavigationLink(value: CampDestination.mentions) { row("Erwähnungen", symbol: "at") }
                    if rights.readsInbox { NavigationLink(value: CampDestination.inbox) { row("Eingang", symbol: "tray") } }
                    NavigationLink(value: CampDestination.notifications) { row("Benachrichtigungen", symbol: "bell") }
                }
                Section("Einteilung") {
                    NavigationLink(value: CampDestination.rooms) { row("Zimmer und Zelte", symbol: "bed.double") }
                    NavigationLink(value: CampDestination.trips) { row("Fahrten", symbol: "car") }
                    NavigationLink(value: CampDestination.groups) { row("Programmgruppen", symbol: "person.3") }
                    NavigationLink(value: CampDestination.shifts) { row("Schichtplan", symbol: "calendar.badge.clock") }
                    NavigationLink(value: CampDestination.swaps) { row("Diensttausch", symbol: "arrow.left.arrow.right") }
                    NavigationLink(value: CampDestination.count) { row("Abzählen", symbol: "checklist") }
                }
                Section("Weiteres") {
                    Button { dismiss(); showAllCamps() } label: { row("Alle Lager", symbol: "tent") }
                }
                Section {} footer: { Text("Oben links wechselst du zurück zur Programm-Ansicht.") }
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Mehr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schliessen", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: CampDestination.self) { destination in
                switch destination {
                case .meetings: CampMeetingsView()
                case .mentions: CampMentionsView()
                case .inbox: CampInboxView()
                case .notifications: CampNotificationsView()
                case .rooms: CampRoomsView()
                case .trips: CampTripsView()
                case .groups: CampGroupsView()
                case .swaps: CampSwapsView(personId: profile.id)
                case .count: CampCountView()
                case .shifts: CampShiftsView(personId: profile.id)
                case .notices: EmptyView()
                }
            }
            .onAppear {
                // A tapped push leads straight to its target.
                if let destination = active.destination, destination != .notices { path = [destination]; active.destination = nil }
            }
            .sheet(isPresented: $showsProfile) { ProfileView(profile: profile) }
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: symbol).foregroundStyle(Color.ceviAccent).frame(width: Size.touchTarget / 2).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.ceviOnSurface)
            Spacer(minLength: Spacing.s2)
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
        }
        .frame(minHeight: Size.touchTarget)
        .contentShape(.rect)
    }
}
