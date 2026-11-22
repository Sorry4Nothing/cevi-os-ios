import SwiftUI

/// Root of L33 inside a navigation stack.
struct CampDocumentsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampDocumentsModel?

    var body: some View {
        Group { if let model { CampDocumentsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampDocumentsModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L33: «Dokumente». A tap opens the link at the storage place in the system; the app loads no bytes.
struct CampDocumentsScreen: View {
    @Bindable var model: CampDocumentsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Dokumente werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Dokumente")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.query, prompt: "Dokumente durchsuchen")
        .onChange(of: model.query) { model.reloadSoon() }
        .onChange(of: model.type) { Task { await model.load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Typ", selection: $model.type) {
                        Text("Alle Typen").tag(CampDocumentTypeFilter?.none)
                        ForEach(CampDocumentTypeFilter.allCases) { Text(CampStorageText.filterName($0)).tag(CampDocumentTypeFilter?.some($0)) }
                    }
                } label: {
                    Label("Nach Typ filtern", systemImage: model.type == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let name = model.active.camp?.title { Text(name).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
        if let type = model.type {
            HStack {
                // Not only the symbol: the active filter is named.
                Label("Nur \(CampStorageText.filterName(type))", systemImage: "line.3.horizontal.decrease.circle.fill").font(.subheadline.bold())
                Spacer(minLength: Spacing.s2)
                Button("Zurücksetzen") { model.type = nil }.frame(minHeight: Size.touchTarget)
            }
            .foregroundStyle(Color.ceviOnSecondaryContainer)
        }
        if model.documents.isEmpty {
            StateView(symbol: model.isFiltered ? "magnifyingglass" : "doc", title: "Keine Dokumente",
                      message: model.isFiltered ? "Ändere die Suche oder den Filter." : "Hier erscheinen die Dokumente des Lagers, sobald sie eingetragen sind.")
                .frame(minHeight: 320)
        } else {
            CampOnSiteCard {
                VStack(spacing: 0) {
                    ForEach(Array(model.documents.enumerated()), id: \.element.id) { index, document in
                        if index > 0 { Divider() }
                        row(document)
                    }
                }
            }
            .padding(.vertical, -Spacing.s2)
        }
    }

    @ViewBuilder private func row(_ document: CampDocument) -> some View {
        if let url = document.file?.openableLink {
            Link(destination: url) { rowContent(document, hint: nil) }
                .accessibilityHint(Text("Öffnet den Ablageort"))
        } else {
            rowContent(document, hint: document.file == nil ? String(localized: "Datei gelöscht") : String(localized: "Kein sicherer Link"))
        }
    }

    private func rowContent(_ document: CampDocument, hint: String?) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: CampStorageText.symbol(document.kind))
                .foregroundStyle(Color.ceviOnSecondaryContainer)
                .frame(width: Size.touchTarget, height: Size.touchTarget)
                .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    Text(document.title).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true)
                    if CampStorageText.isNew(document, now: model.now()) { CampCountChip(text: String(localized: "neu"), tone: .warning) }
                }
                HStack(spacing: Spacing.s2) {
                    Text(CampStorageText.subtitle(document)).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
                    ForEach(document.keywords, id: \.self) { CampCountChip(text: $0) }
                }
                if let hint { Text(hint).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Size.touchTarget)
        .padding(.vertical, Spacing.s2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(CampStorageText.spoken(document, now: model.now()) + (hint.map { ", " + $0 } ?? "")))
    }
}
