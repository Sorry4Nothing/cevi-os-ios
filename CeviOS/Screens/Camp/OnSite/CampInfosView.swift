import SwiftUI

/// Root of L32 inside a navigation stack.
struct CampInfosView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampInfosModel?

    var body: some View {
        Group { if let model { CampInfosScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampInfosModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L32: «Infos».
struct CampInfosScreen: View {
    @Bindable var model: CampInfosModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Infos werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Infos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.canReorder && model.infos.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isReordering ? "Fertig" : "Sortieren") { model.isReordering.toggle() }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let name = model.active.camp?.title { Text(name).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
        if model.showsRestrictedHint {
            CampRoleHint(title: "Einige Abschnitte sind für die Lagerleitung.", message: "Du siehst die übrigen.")
        }
        if model.infos.isEmpty {
            StateView(symbol: "info.circle", title: "Noch keine Infos", message: "Hier erscheinen Lagerhaus, Regeln und Tagesablauf, sobald sie eingetragen sind.").frame(minHeight: 320)
        }
        if model.isReordering {
            Text("Ziehen oder «Nach oben» und «Nach unten» benutzen.").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        ForEach(model.infos) { card($0) }
    }

    private func card(_ info: CampInfo) -> some View {
        CampOnSiteCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(info.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                    Spacer(minLength: Spacing.s2)
                    if info.leadershipOnly { Label("nur Lagerleitung", systemImage: "lock").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                if let text = CampRosterText.trimmed(info.text) { Text(text).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true) }
                ForEach(info.links, id: \.url) { link in
                    if let url = URL(string: link.url), url.scheme == "https" { Link(destination: url) { Label(link.title, systemImage: "link").frame(minHeight: Size.touchTarget) } }
                }
                ForEach(info.files) { file in Link(destination: file.link) { Label(file.displayName, systemImage: "doc").frame(minHeight: Size.touchTarget) } }
                if model.isReordering {
                    HStack {
                        Button { Task { await model.move(info, by: -1) } } label: { Label("Nach oben", systemImage: "arrow.up") }
                            .disabled(!model.canMove(info, by: -1))
                        Button { Task { await model.move(info, by: 1) } } label: { Label("Nach unten", systemImage: "arrow.down") }
                            .disabled(!model.canMove(info, by: 1))
                    }
                    .buttonStyle(.bordered).frame(minHeight: Size.touchTarget)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
