import SwiftUI

/// L35: a portfolio (Ressort) with leader, deputy and notes.
struct CampPortfolioView: View {
    @State private var model: CampPortfolioModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsNote = false
    @State private var collapsed: Set<UUID> = []

    init(active: ActiveCamp, portfolioId: UUID) {
        _model = State(initialValue: CampPortfolioModel(active: active, portfolioId: portfolioId))
    }

    init(model: CampPortfolioModel) { _model = State(initialValue: model) }

    var body: some View {
        Group {
            switch model.phase {
            case .loading: LoadingView(label: "Ressort wird geladen")
            case .failed(let state, _):
                if let state, state.isFullScreen, state != .offline {
                    CampStateView(state: state, notFoundMessage: "Dieses Ressort gibt es nicht mehr.", back: .init(title: "Zu den Aufgaben") { dismiss() }) { Task { await model.load() } }
                } else {
                    StateView.failure(retry: { Task { await model.load() } }, back: .init(title: "Zu den Aufgaben") { dismiss() })
                }
            case .loaded: content
            }
        }
        .navigationTitle(model.portfolio?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .task { await model.load() }
        .sheet(isPresented: $showsNote) { CampNoteSheet(title: String(localized: "Notiz"), initial: "") { text in Task { _ = await model.addNote(text) } } }
    }

    @ViewBuilder private var content: some View {
        if let portfolio = model.portfolio {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text("Ressort im \(model.active.title)").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    CampBannerStack()
                    if let error = model.error { ErrorRow(text: error) }
                    VStack(spacing: 0) {
                        row("Verantwortlich", CampTaskText.personName(name: portfolio.leader?.name, ceviName: portfolio.leader?.ceviName) ?? String(localized: "Niemand"))
                        Divider()
                        row("Stellvertretung", CampTaskText.personName(name: portfolio.deputy?.name, ceviName: portfolio.deputy?.ceviName) ?? String(localized: "Niemand"))
                    }
                    .ceviCard()
                    Text("Notizen").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
                    if model.notes.isEmpty {
                        VStack(spacing: Spacing.s1) {
                            Text("Noch keine Notizen").font(.title(.title2)).foregroundStyle(Color.ceviOnSurface)
                            Text(model.canWriteNotes ? "Schreib die erste Notiz für dieses Ressort." : "Hier erscheinen die Notizen der Ressortleitung.")
                                .foregroundStyle(Color.ceviOnSurfaceVariant)
                        }
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, Spacing.s6)
                    }
                    ForEach(model.notes) { note in noteCard(note) }
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax).frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
            .ceviScreenBackground()
            .safeAreaInset(edge: .bottom) {
                if model.canWriteNotes {
                    CampNewTaskButton(title: "Notiz") { showsNote = true }.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, Spacing.s4)
                }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(label).foregroundStyle(Color.ceviOnSurfaceVariant); Spacer(minLength: Spacing.s2); Text(value) }
            VStack(alignment: .leading) { Text(label).foregroundStyle(Color.ceviOnSurfaceVariant); Text(value) }
        }
        .foregroundStyle(Color.ceviOnSurface).frame(minHeight: Size.touchTarget)
        .accessibilityElement(children: .combine)
    }

    private func noteCard(_ note: CampPortfolioNote) -> some View {
        let isCollapsed = collapsed.contains(note.id)
        let author = CampTaskText.personName(name: note.author?.name, ceviName: note.author?.ceviName)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(note.text).lineLimit(isCollapsed ? 2 : nil).foregroundStyle(Color.ceviOnSurface)
            Text([author, note.createdAt.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: ", "))
                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            Button(isCollapsed ? "Aufklappen" : "Zuklappen") { if isCollapsed { collapsed.remove(note.id) } else { collapsed.insert(note.id) } }
                .buttonStyle(.ceviText)
        }
        .frame(maxWidth: .infinity, alignment: .leading).ceviCard()
    }
}

#if DEBUG
#Preview("L35 Normal") { CampPreview.portfolioScreen() }
#Preview("L35 Nacht") { CampPreview.portfolioScreen().preferredColorScheme(.dark) }
#Preview("L35 Laden") { CampPreview.portfolioScreen(phase: .loading) }
#Preview("L35 Leer") { CampPreview.portfolioScreen(empty: true) }
#Preview("L35 Fehler") { CampPreview.portfolioScreen(phase: .failed(state: nil, text: "x")) }
#Preview("L35 Textgrösse AX3") { CampPreview.portfolioScreen().dynamicTypeSize(.accessibility3) }
#endif
