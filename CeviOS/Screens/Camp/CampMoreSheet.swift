import SwiftUI

/// L37: «Mehr» of the camp view. Only entries whose target exists and that the role may open.
struct CampMoreSheet: View {
    let profile: Profile
    let showAllCamps: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ActiveCamp.self) private var active
    @State private var showsProfile = false
    @State private var path: [CampDestination] = []

    /// Entries whose target exists and that the role may open.
    private var rights: CampCommsRights { CampCommsRights(role: active.role, readOnly: active.isReadOnly) }
    private var onSite: CampOnSiteRights { CampOnSiteRights(role: active.role, readOnly: active.isReadOnly) }
    private var checkRights: CampCheckRights { CampCheckRights(role: active.role, readOnly: active.isReadOnly) }
    private var storage: CampStorageRights { CampStorageRights(role: active.role, readOnly: active.isReadOnly) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { showsProfile = true } label: { row("Profil", symbol: "person.crop.circle", showsChevron: true) }
                }
                Section("Lager") {
                    NavigationLink(value: CampDestination.meetings) { row("Hoecks", symbol: "calendar") }
                    NavigationLink(value: CampDestination.mentions) { row("Erwähnungen", symbol: "at") }
                    if rights.readsInbox { NavigationLink(value: CampDestination.inbox) { row("Eingang", symbol: "tray") } }
                    NavigationLink(value: CampDestination.notifications) { row("Benachrichtigungen", symbol: "bell") }
                    if checkRights.reads { NavigationLink(value: CampDestination.check) { row("Lager-Check", symbol: "checkmark.seal") } }
                }
                Section("Einteilung") {
                    NavigationLink(value: CampDestination.rooms) { row("Zimmer und Zelte", symbol: "bed.double") }
                    NavigationLink(value: CampDestination.trips) { row("Fahrten", symbol: "car") }
                    NavigationLink(value: CampDestination.groups) { row("Programmgruppen", symbol: "person.3") }
                    NavigationLink(value: CampDestination.shifts) { row("Schichtplan", symbol: "calendar.badge.clock") }
                    NavigationLink(value: CampDestination.swaps) { row("Diensttausch", symbol: "arrow.left.arrow.right") }
                    NavigationLink(value: CampDestination.count) { row("Abzählen", symbol: "checklist") }
                }
                Section("Im Lager") {
                    if active.role == .campLeader { NavigationLink(value: CampDestination.attendance) { row("Anwesenheit", symbol: "checklist.checked") } }
                    NavigationLink(value: CampDestination.dayPages) { row("Tagesseiten", symbol: "doc.text") }
                    if onSite.seesShopping { NavigationLink(value: CampDestination.shopping) { row("Einkaufsliste", symbol: "cart") } }
                    NavigationLink(value: CampDestination.packing) { row("Packliste", symbol: "suitcase") }
                    NavigationLink(value: CampDestination.emergency) { row("Notfall", symbol: "cross") }
                    NavigationLink(value: CampDestination.infos) { row("Infos", symbol: "info.circle") }
                }
                Section("Ablage") {
                    NavigationLink(value: CampDestination.documents) { row("Dokumente", symbol: "doc") }
                    if storage.seesAddressBook { NavigationLink(value: CampDestination.addressBook) { row("Adressbuch", symbol: "person.crop.rectangle") } }
                    if active.role == .campLeader || active.role == .leader { NavigationLink(value: CampDestination.handouts) { row("Aushänge", symbol: "printer") } }
                    NavigationLink(value: CampDestination.search) { row("Suche", symbol: "magnifyingglass") }
                }
                Section("Weiteres") {
                    Button { dismiss(); showAllCamps() } label: { row("Alle Lager", symbol: "tent", showsChevron: true) }
                }
                Section {} footer: { Text("Oben links wechselst du zurück zur Programm-Ansicht.") }
            }
            // Section titles in the text color instead of the system grey (3:1 on the light surface).
            .environment(\.headerProminence, .increased)
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
                case .attendance: CampAttendanceView(profile: profile)
                case .dayPages: CampDayListView(profile: profile)
                case .shopping: CampShoppingView()
                case .packing: CampPackingView()
                case .emergency: CampEmergencyView()
                case .infos: CampInfosView()
                case .documents: CampDocumentsView()
                case .addressBook: CampAddressBookView()
                case .search: CampSearchView()
                case .handouts: CampHandoutsView()
                case .check: CampCheckView()
                case .notices, .tasks: EmptyView()
                }
            }
            .onAppear {
                // A tapped push leads straight to its target.
                if let destination = active.destination, destination != .notices { path = [destination]; active.destination = nil }
            }
            .sheet(isPresented: $showsProfile) { ProfileView(profile: profile) }
        }
    }

    /// A navigation link draws its own chevron; only the buttons need one.
    private func row(_ title: LocalizedStringKey, symbol: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: symbol).foregroundStyle(Color.ceviAccent).frame(width: Size.touchTarget / 2).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.ceviOnSurface)
            Spacer(minLength: Spacing.s2)
            if showsChevron { Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true) }
        }
        .frame(minHeight: Size.touchTarget)
        .contentShape(.rect)
    }
}
