import SwiftUI

/// Root of L22 inside a navigation stack: creates the model for the open camp.
struct CampGroupsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampGroupsModel?

    var body: some View {
        Group { if let model { CampGroupsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampGroupsModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L22: «Programmgruppen».
struct CampGroupsScreen: View {
    @Bindable var model: CampGroupsModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsShuffle = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Programmgruppen werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Programmgruppen")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsShuffle, onDismiss: model.cancelShuffle) { CampShuffleSheet(model: model) { showsShuffle = false } }
    }

    @ViewBuilder private var content: some View {
        if model.groups.isEmpty {
            StateView(symbol: "person.3", title: "Noch keine Gruppen", message: "Lege Programmgruppen an oder lass sie mischen.",
                      primary: model.canShuffle ? .init(title: "Automatisch mischen", symbol: "shuffle") { open() } : nil)
                .frame(minHeight: 320)
        } else {
            if model.canShuffle {
                Button { open() } label: { Label("Automatisch mischen", systemImage: "shuffle") }
                    .buttonStyle(CeviPrimaryButtonStyle(expands: false))
            }
            if model.rights.isLockedByRole { CampRoleHint(title: "Nur lesen.", message: "Die Gruppen teilt die Lagerleitung ein.") }
            ForEach(model.groups) { card($0) }
            if model.withoutGroup > 0 {
                Text("Ohne Gruppe: \(CampRosterText.children(model.withoutGroup))").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
    }

    private func open() {
        model.beginShuffle()
        showsShuffle = true
        Task { await model.suggest() }
    }

    private func card(_ group: CampGroup) -> some View {
        let leaders = CampGroupsModel.leaders(group)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s2)
                CampCountChip(text: CampRosterText.children(group.participants.count))
            }
            Text("Leitung").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            if leaders.isEmpty {
                Text("Noch keine Leitung").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            } else {
                CampPeopleLine(names: leaders)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .combine)
    }
}

/// «Vorschau: gemischt»: the mix with the number of children per group; «Übernehmen» writes it.
struct CampShuffleSheet: View {
    @Bindable var model: CampGroupsModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let error = model.error { ErrorRow(text: error) }
                    Text("Vorschau: gemischt").font(.title(.title2)).accessibilityAddTraits(.isHeader)
                    Text("So werden die Gruppen neu verteilt. Leitende bleiben.").foregroundStyle(Color.ceviOnSurfaceVariant)
                    Stepper(value: $model.shuffleCount, in: CampGroupsModel.countRange) { Text("Anzahl Gruppen: \(model.shuffleCount)") }
                        .frame(minHeight: Size.touchTarget)
                        .onChange(of: model.shuffleCount) { Task { await model.suggest() } }
                    if model.isSuggesting {
                        ProgressView("Vorschau wird berechnet").frame(maxWidth: .infinity)
                    } else if let suggestion = model.suggestion {
                        ForEach(suggestion.groups, id: \.number) { group in
                            HStack {
                                Text(group.name).font(.headline)
                                Spacer(minLength: Spacing.s2)
                                CampCountChip(text: CampRosterText.children(group.count))
                            }
                            .frame(minHeight: Size.touchTarget)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Button("Neu mischen", systemImage: "shuffle") { Task { await model.suggest() } }.buttonStyle(.ceviText)
                    Button("Übernehmen") { Task { if await model.confirm() { close() } } }
                        .buttonStyle(.ceviPrimary).disabled(model.suggestion == nil || model.isSuggesting)
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .ceviScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) } }
        }
    }
}

#if DEBUG
#Preview("L22 Normal") { CampRosterPreview.groups() }
#Preview("L22 Nacht") { CampRosterPreview.groups().preferredColorScheme(.dark) }
#Preview("L22 Laden") { CampRosterPreview.groups(phase: .loading) }
#Preview("L22 Leer") { CampRosterPreview.groups(empty: true) }
#Preview("L22 Fehler") { CampRosterPreview.groups(phase: .failed(state: nil, text: "x")) }
#Preview("L22 Fehler beim Speichern") { CampRosterPreview.groups(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L22 Vorschau mischen") { CampRosterPreview.shuffle() }
#Preview("L22 Vorschau mischen Nacht") { CampRosterPreview.shuffle().preferredColorScheme(.dark) }
#Preview("L22 Nur lesen (Leitung)") { CampRosterPreview.groups(role: .leader) }
#Preview("L22 Lager abgeschlossen") { CampRosterPreview.groups(status: "abgeschlossen") }
#Preview("L22 Textgrösse AX3") { CampRosterPreview.groups().dynamicTypeSize(.accessibility3) }
#endif
