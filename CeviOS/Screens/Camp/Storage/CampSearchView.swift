import SwiftUI

/// Root of L36 inside a navigation stack.
struct CampSearchView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampSearchModel?

    var body: some View {
        Group { if let model { CampSearchScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampSearchModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L36: «Suche». Only what the server returns for the role; a hit opens the screen of its kind where the app has one.
struct CampSearchScreen: View {
    @Bindable var model: CampSearchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Suche wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: nil, refresh: { await model.load() }) { content }
        }
        .navigationTitle("Suche")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Im Lager suchen")
        .onChange(of: model.query) { model.reloadSoon() }
        .onChange(of: model.type) { Task { await model.load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Typ", selection: $model.type) {
                        Text("Alle Typen").tag(CampSearchType?.none)
                        ForEach(model.storage.searchTypes, id: \.self) { Text(CampStorageText.typeName($0)).tag(CampSearchType?.some($0)) }
                    }
                } label: {
                    Label("Nach Typ filtern", systemImage: model.type == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let type = model.type {
            HStack {
                Label("Nur \(CampStorageText.typeName(type))", systemImage: "line.3.horizontal.decrease.circle.fill").font(.subheadline.bold())
                Spacer(minLength: Spacing.s2)
                Button("Zurücksetzen") { model.type = nil }.frame(minHeight: Size.touchTarget)
            }
            .foregroundStyle(Color.ceviOnSecondaryContainer)
        }
        if let term = model.term {
            if model.hits.isEmpty {
                StateView(symbol: "magnifyingglass", title: "Keine Treffer", message: "Prüfe die Schreibweise von «\(term)».").frame(minHeight: 320)
            }
            ForEach(model.groups) { group in
                CampSectionTitle(LocalizedStringKey(group.title))
                CampOnSiteCard {
                    VStack(spacing: 0) {
                        ForEach(Array(group.hits.enumerated()), id: \.element.id) { index, hit in
                            if index > 0 { Divider() }
                            row(hit)
                        }
                    }
                }
                .padding(.vertical, -Spacing.s2)
            }
        } else {
            StateView(symbol: "magnifyingglass", title: "Im Lager suchen", message: "Gib mindestens zwei Zeichen ein.").frame(minHeight: 320)
        }
    }

    @ViewBuilder private func row(_ hit: CampSearchHit) -> some View {
        if let destination = CampStorageText.destination(hit.type) {
            NavigationLink(value: destination) { rowContent(hit, chevron: true) }.buttonStyle(.plain)
        } else {
            rowContent(hit, chevron: false)
        }
    }

    private func rowContent(_ hit: CampSearchHit, chevron: Bool) -> some View {
        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(hit.title).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true)
                if let excerpt = CampRosterText.trimmed(hit.excerpt) {
                    Text(excerpt).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.s2)
            if chevron { Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true) }
        }
        .frame(minHeight: Size.touchTarget)
        .padding(.vertical, Spacing.s2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
