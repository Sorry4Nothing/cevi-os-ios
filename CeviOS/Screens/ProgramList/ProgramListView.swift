import SwiftUI

struct ProgramListView: View {
    @Environment(AppState.self) private var appState
    @State private var model = ProgramListModel()
    @Binding var path: [UUID]
    @State private var destination: EventDestination?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.state {
                case .loading:
                    LoadingView(label: "Programme werden geladen")
                case .failed(let text) where model.sections.isEmpty:
                    StateView(symbol: "exclamationmark.triangle", title: "Etwas ist schiefgelaufen", message: "\(text)", tone: .error,
                              primary: .init(title: "Nochmals versuchen", symbol: "arrow.clockwise") {
                                  Task { await model.load(client: appState.client) }
                              })
                default:
                    list
                }
            }
            .navigationTitle("Programme")
            .navigationSubtitle(ProgramListModel.subtitle(for: appState.profile) ?? "")
            .campSwitcher()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Termin vorschlagen", systemImage: "calendar.badge.plus") { destination = .suggestEvent }
                        Button("Raum anfragen", systemImage: "door.left.hand.open") { destination = .requestRoom }
                        Button("Meine Raumanfragen", systemImage: "list.bullet") { destination = .myRoomRequests }
                    } label: {
                        Label("Termine und Räume", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in ProgramDetailView(programId: id) }
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .suggestEvent: SuggestEventView()
                case .requestRoom: RequestRoomView(fromList: false)
                case .myRoomRequests: MyRoomRequestsView()
                }
            }
        }
        .task { await model.load(client: appState.client) }
        // Back from a detail: answers given there show up in the list right away.
        .onChange(of: path) { _, new in
            if new.isEmpty { Task { await model.load(client: appState.client) } }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.sections.isEmpty {
            StateView(symbol: "calendar", title: "Keine Termine für dich",
                      message: "Es gibt gerade keine Termine für deine Gruppen. Sobald die Leitung neue einträgt, siehst du sie hier.",
                      primary: .init(title: "Aktualisieren", symbol: "arrow.clockwise") {
                Task { await model.load(client: appState.client) }
            })
        } else {
            ScrollView {
                // Not lazy: at most 120 days of programs, and every card stays in the accessibility tree.
                VStack(alignment: .leading, spacing: Spacing.s5) {
                    if case .failed(let text) = model.state {
                        ErrorRow(text: text)
                    }
                    ForEach(model.sections) { section in
                        DaySectionView(section: section)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load(client: appState.client) }
            .ceviScreenBackground()
        }
    }
}
