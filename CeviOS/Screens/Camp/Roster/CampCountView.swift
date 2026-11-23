import SwiftUI

/// Root of L25 inside a navigation stack: creates the model for the open camp.
struct CampCountView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampCountModel?

    var body: some View {
        Group { if let model { CampCountScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampCountModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L25: «Abzählen», with the shared ticks and the filter chips.
struct CampCountScreen: View {
    @Bindable var model: CampCountModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsReset = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Abzählliste wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error,
                       notice: model.noticeData(undo: model.snapshot == nil ? nil : { Task { await model.undoReset() } }),
                       refresh: { await model.load() }) { content }
        }
        .navigationTitle("Abzählen")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Liste zurücksetzen?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { Task { await model.reset() } }
        } message: { Text("Alle Haken verschwinden für alle.") }
    }

    @ViewBuilder private var content: some View {
        if let name = model.active.camp?.title { Text(name).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
        if model.rows.isEmpty, model.scope == .all {
            StateView(symbol: "person.2", title: "Keine Personen", message: "Sobald Personen im Lager sind, kannst du sie abzählen.").frame(minHeight: 320)
        } else {
            summary
            filters
            if model.rows.isEmpty {
                Text("Hier ist niemand.").foregroundStyle(Color.ceviOnSurfaceVariant).padding(.vertical, Spacing.s4)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        rowView(row)
                        if row.id != model.rows.last?.id { Divider().padding(.leading, Spacing.s6 + Size.touchTarget) }
                    }
                }
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
            }
            if model.rights.resets {
                Button { confirmsReset = true } label: { Label("Zurücksetzen", systemImage: "arrow.counterclockwise") }.buttonStyle(.ceviText)
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(model.present) von \(model.total)").font(.title(.display)).foregroundStyle(Color.ceviOnSurface)
            Spacer(minLength: Spacing.s2)
            Text("für alle sichtbar").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(model.present) von \(model.total) sind da, für alle sichtbar"))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                chip("Alle", .all)
                chip("Leitung", .team)
                ForEach(model.groups) { chip(Text($0.name), .group($0.id)) }
            }
        }
    }

    private func chip(_ title: LocalizedStringKey, _ scope: CampCountModel.Scope) -> some View { chip(Text(title), scope) }

    private func chip(_ title: Text, _ scope: CampCountModel.Scope) -> some View {
        let isOn = model.scope == scope
        return Button { Task { await model.select(scope) } } label: {
            HStack(spacing: Spacing.s1) {
                if isOn { Image(systemName: "checkmark").accessibilityHidden(true) }
                title
            }
            .font(.subheadline.bold())
            .padding(.horizontal, Spacing.s4)
            .frame(minHeight: Size.touchTarget)
            .foregroundStyle(isOn ? Color.ceviSurface : Color.ceviOnSurface)
            .background(isOn ? Color.ceviAccent : Color.clear, in: .capsule)
            .overlay(Capsule().stroke(Color.ceviOutline, lineWidth: isOn ? 0 : Size.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private func rowView(_ row: CampCountModel.Row) -> some View {
        let content = HStack(spacing: Spacing.s3) {
            Image(systemName: row.checked ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(row.checked ? Color.ceviAccent : Color.ceviOnSurfaceVariant).accessibilityHidden(true)
            Text(row.label).foregroundStyle(Color.ceviOnSurface)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s4)
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget + Spacing.s3, alignment: .leading)
        .contentShape(.rect)
        if model.rights.ticks {
            Button { Task { await model.toggle(row) } } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(row.label), \(row.checked ? "da" : "noch nicht da")"))
                .accessibilityAddTraits(.isToggle)
        } else {
            content.accessibilityElement(children: .ignore).accessibilityLabel(Text("\(row.label), \(row.checked ? "da" : "noch nicht da")"))
        }
    }
}

#if DEBUG
#Preview("L25 Normal") { CampRosterPreview.count() }
#Preview("L25 Nacht") { CampRosterPreview.count().preferredColorScheme(.dark) }
#Preview("L25 Laden") { CampRosterPreview.count(phase: .loading) }
#Preview("L25 Leer") { CampRosterPreview.count(empty: true) }
#Preview("L25 Fehler") { CampRosterPreview.count(phase: .failed(state: nil, text: "x")) }
#Preview("L25 Ohne Netz") { CampRosterPreview.count(offline: true) }
#Preview("L25 Rückgängig") { CampRosterPreview.count(notice: .init(title: "Liste zurückgesetzt.", message: "Alle Haken sind entfernt."), undo: true) }
#Preview("L25 Gleichzeitig") { CampRosterPreview.count(notice: .init(title: "Schon abgehakt.", message: "Jemand war schneller. Die Liste ist aktuell.")) }
#Preview("L25 Nur lesen") { CampRosterPreview.count(role: .readOnly) }
#Preview("L25 Textgrösse AX3") { CampRosterPreview.count().dynamicTypeSize(.accessibility3) }
#endif
