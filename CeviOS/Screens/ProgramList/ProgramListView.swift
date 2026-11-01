import SwiftUI

struct ProgramListView: View {
    @Environment(AppState.self) private var appState
    @State private var model = ProgramListModel()
    @Binding var path: [UUID]

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
            .navigationDestination(for: UUID.self) { id in ProgramDetailView(programId: id) }
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
            StateView.empty(title: "Keine Programme", message: "In den nächsten Monaten ist nichts geplant.") {
                Task { await model.load(client: appState.client) }
            }
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
