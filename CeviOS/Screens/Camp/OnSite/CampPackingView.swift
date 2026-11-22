import SwiftUI

/// Root of L29 inside a navigation stack.
struct CampPackingView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampPackingModel?

    var body: some View {
        Group { if let model { CampPackingScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampPackingModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L29: «Packliste», tick off what is packed.
struct CampPackingScreen: View {
    @Bindable var model: CampPackingModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsAdd = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Packliste wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Packliste")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if model.canAdd && model.phase == .loaded { CampMainAction(title: "Punkt hinzufügen") { showsAdd = true } }
        }
        .sheet(isPresented: $showsAdd) { CampPackingAddSheet(model: model) { showsAdd = false }.presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private var content: some View {
        if model.total == 0 {
            StateView(symbol: "suitcase", title: "Noch keine Packliste",
                      message: model.canAdd ? "Füge Punkte hinzu." : "Hier erscheint die Packliste, sobald sie eingetragen ist.").frame(minHeight: 320)
        } else {
            Text(model.progress).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.updatesFrequently)
            ForEach(model.sections) { section in
                CampSectionTitle(LocalizedStringKey(section.title))
                VStack(spacing: 0) {
                    ForEach(section.rows) { row in
                        rowView(row)
                        if row.id != section.rows.last?.id { Divider().padding(.leading, Spacing.s4 + Size.touchTarget) }
                    }
                }
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
                .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
            }
        }
    }

    private func rowView(_ row: CampPackingModel.Row) -> some View {
        var parts = [row.text, row.checked ? String(localized: "eingepackt") : String(localized: "noch nicht eingepackt")]
        if row.leadershipOnly { parts.append(String(localized: "nur Lagerleitung")) }
        if row.isOwn { parts.append(String(localized: "eigener Punkt")) }
        let content = HStack(spacing: Spacing.s3) {
            Image(systemName: row.checked ? "checkmark.circle.fill" : "circle").font(.title2)
                .foregroundStyle(row.checked ? Color.ceviAccent : Color.ceviOnSurfaceVariant).accessibilityHidden(true)
            Text(row.text).foregroundStyle(row.checked ? Color.ceviOnSurfaceVariant : Color.ceviOnSurface).strikethrough(row.checked)
            Spacer(minLength: Spacing.s2)
            if row.leadershipOnly { Label("nur Lagerleitung", systemImage: "lock").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
            if row.isOwn { Label("eigener Punkt", systemImage: "person").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant).labelStyle(.titleOnly) }
        }
        .padding(.horizontal, Spacing.s4)
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget + Spacing.s3, alignment: .leading)
        .contentShape(.rect)
        return Group {
            if model.ticks {
                Button { Task { await model.toggle(row) } } label: { content }.buttonStyle(.plain).accessibilityAddTraits(.isToggle)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(parts.joined(separator: ", ")))
    }
}

/// «Punkt hinzufügen»: section (an existing one or a new one) and text. The camp leadership may mark the point.
struct CampPackingAddSheet: View {
    let model: CampPackingModel
    let close: () -> Void
    @State private var section = ""
    @State private var text = ""
    @State private var leadershipOnly = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let error = model.error { ErrorRow(text: error) }
                    Text("Abschnitt").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Abschnitt", text: $section).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                    if !model.sectionNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.s2) {
                                ForEach(model.sectionNames, id: \.self) { name in
                                    Button { section = name } label: {
                                        Text(name).font(.subheadline.bold()).padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
                                            .foregroundStyle(Color.ceviOnSecondaryContainer).background(Color.ceviSecondaryContainer, in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(Text("Übernimmt den Abschnitt"))
                                }
                            }
                        }
                    }
                    Text("Punkt").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Punkt", text: $text).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                    if model.addsToTemplate { Toggle("Nur Lagerleitung", isOn: $leadershipOnly).frame(minHeight: Size.touchTarget) }
                    Button("Hinzufügen") {
                        Task { if await model.add(section: section, text: text, leadershipOnly: leadershipOnly) { close() } }
                    }
                    .buttonStyle(.ceviPrimary)
                }
                .padding(Spacing.s4)
            }
            .ceviScreenBackground()
            .navigationTitle("Punkt hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark", action: close) } }
        }
    }
}
