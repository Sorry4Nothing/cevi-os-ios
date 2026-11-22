import SwiftUI

/// The list of camp days (Mehr, «Tagesseiten»); a tap opens the day page.
struct CampDayListView: View {
    let profile: Profile
    @Environment(ActiveCamp.self) private var active
    @Environment(\.dismiss) private var dismiss
    @State private var model: CampDayListModel?

    var body: some View {
        Group {
            if let model {
                CampPhaseView(phase: model.phase, loading: "Tagesseiten werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
                    CampScroll(staleSince: model.staleSince, error: model.error, notice: nil, refresh: { await model.load() }) { list(model) }
                }
            } else { Color.clear }
        }
        .navigationTitle("Tagesseiten")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard model == nil else { return }
            let created = CampDayListModel(active: active)
            model = created
            await created.load()
        }
    }

    @ViewBuilder private func list(_ model: CampDayListModel) -> some View {
        if model.rows.isEmpty {
            StateView(symbol: "calendar", title: "Noch keine Lagertage", message: "Die Tage erscheinen, sobald die Lagerleitung den Zeitplan angelegt hat.").frame(minHeight: 320)
        }
        ForEach(model.rows) { row in
            NavigationLink { CampDayPageView(dayId: row.id, date: row.date, personId: profile.id) } label: {
                CampOnSiteCard {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text(row.title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                            Text(row.chief.map { String(localized: "Tageschef: \($0)") } ?? (row.hasPage ? String(localized: "Ohne Tageschef") : String(localized: "Noch nichts eingetragen")))
                                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                        }
                        Spacer(minLength: Spacing.s2)
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
                    }
                    .frame(minHeight: Size.touchTarget)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Root of L27 inside a navigation stack.
struct CampDayPageView: View {
    let dayId: UUID
    let date: Date
    let personId: UUID
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampDayPageModel?

    var body: some View {
        Group { if let model { CampDayPageScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampDayPageModel(active: active, personId: personId, dayId: dayId, date: date)
                model = created
                await created.load()
            }
    }
}

/// L27: «Tagesseite».
struct CampDayPageScreen: View {
    @Bindable var model: CampDayPageModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Tagesseite wird geladen", notFound: "Diese Tagesseite gibt es nicht mehr.", back: .init(title: "Zurück") { dismiss() },
                      retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle(model.headline)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        if let name = model.active.camp?.title { Text(name).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
        if model.isEmpty {
            StateView(symbol: "doc.text", title: "Noch nichts für diesen Tag", message: "Hier erscheinen Tageschef, Wichtiges und To-dos, sobald sie eingetragen sind.").frame(minHeight: 320)
        }
        if let chief = model.chiefName {
            CampSectionTitle("Tageschef")
            CampOnSiteCard { Text(chief).font(.headline).foregroundStyle(Color.ceviOnSurface) }.accessibilityElement(children: .combine)
        }
        if let weather = model.weather {
            CampSectionTitle("Wetter")
            CampOnSiteCard {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Label(weather, systemImage: "cloud.sun").foregroundStyle(Color.ceviOnSurface)
                    ForEach(model.weatherWarnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.subheadline.bold()).foregroundStyle(Color.ceviOnWarningContainer) }
                }
            }
            .accessibilityElement(children: .combine)
        }
        blockSection("Wichtig", model.important)
        blockSection("Ideen", model.ideas)
        if !model.pictures.isEmpty {
            CampSectionTitle("Programmbild")
            ForEach(model.pictures) { block in
                CampOnSiteCard {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        if !block.text.isEmpty { Text(block.text).foregroundStyle(Color.ceviOnSurface) }
                        if let file = block.file { Link(destination: file.link) { Label(file.displayName, systemImage: "photo").frame(minHeight: Size.touchTarget) } }
                    }
                }
            }
        }
        if let note = model.note {
            CampSectionTitle("Notiz")
            CampOnSiteCard { Text(note).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true) }
        }
        if !model.todos.isEmpty {
            CampSectionTitle("To-dos")
            CampDayTodoList(model: model, today: model.now(), canPostpone: true)
        }
    }

    @ViewBuilder private func blockSection(_ title: LocalizedStringKey, _ blocks: [CampDayBlock]) -> some View {
        if !blocks.isEmpty {
            CampSectionTitle(title)
            CampOnSiteCard {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    ForEach(blocks) { Text($0.text).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
