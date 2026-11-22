import SwiftUI

/// L13 for one meeting; creates its model.
struct CampProtocolView: View {
    @State private var model: CampProtocolModel

    init(active: ActiveCamp, meetingId: UUID) { _model = State(initialValue: CampProtocolModel(active: active, meetingId: meetingId)) }
    init(model: CampProtocolModel) { _model = State(initialValue: model) }

    var body: some View { CampProtocolScreen(model: model).task { await model.load() } }
}

/// L13: the protocol of a meeting (row, attendees, agenda, resolutions) with the conflict of U7.
struct CampProtocolScreen: View {
    @Bindable var model: CampProtocolModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CampResolution?
    @State private var showsNew = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Protokoll wird geladen", notFound: "Dieses Protokoll gibt es nicht mehr.",
                      back: .init(title: "Zu den Hoecks") { dismiss() }, retry: { Task { await model.load() } }) {
            if let conflict = model.conflict { conflictView(conflict) } else {
                CampScroll(staleSince: model.staleSince, error: model.error, refresh: { await model.load() }) { content }
                    .safeAreaInset(edge: .bottom) { if model.canEdit, model.minutes != nil { saveBar } }
            }
        }
        .navigationTitle("Protokoll")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { resolution in CampResolutionSheet(initial: resolution.text, title: "Beschluss") { text in Task { _ = await model.saveResolution(text, resolution: resolution) } } }
        .sheet(isPresented: $showsNew) { CampResolutionSheet(initial: "", title: "Neuer Beschluss") { text in Task { _ = await model.saveResolution(text, resolution: nil) } } }
    }

    private func conflictView(_ conflict: CampProtocolModel.Conflict) -> some View {
        CampConflictView(title: String(localized: "Jemand hat das Protokoll gerade geändert."), subject: conflict.current.title,
                         mineAuthor: String(localized: "Du, eben jetzt"), currentAuthor: String(localized: "Aktuelle Fassung"), fields: conflict.fields) { choice in
            Task { await model.resolve(choice) }
        }
    }

    @ViewBuilder private var content: some View {
        if let meeting = model.meeting {
            Text("\(meeting.title), \(CampCommsText.meetingDate(meeting.date, time: meeting.time))")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        if model.saveFailed {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Label("Das hat nicht geklappt", systemImage: "exclamationmark.triangle.fill").font(.headline)
                Text("Deine Eingabe ist noch da. Versuche es nochmals.").font(.subheadline)
                Button("Nochmals versuchen") { Task { await model.save() } }.buttonStyle(.ceviText)
            }
            .foregroundStyle(Color.ceviOnErrorContainer).frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.s4)
            .background(Color.ceviErrorContainer, in: Radius.shape(Radius.md)).accessibilityElement(children: .contain)
        }
        if model.minutes != nil { rowCard }
        if !model.attendees.isEmpty {
            heading("Anwesende")
            FlowLayout(spacing: Spacing.s2) {
                ForEach(model.attendees) { person in
                    let name = person.name ?? person.ceviName ?? ""
                    HStack(spacing: Spacing.s2) {
                        Text(CampCommsText.initials(name)).font(.caption2.bold()).foregroundStyle(Color.ceviOnPrimary)
                            .frame(width: 28, height: 28).background(Color.ceviAccent, in: Circle()).accessibilityHidden(true)
                        Text(name).foregroundStyle(Color.ceviOnSurface)
                    }
                    .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
                    .background(Color.ceviSecondaryContainer, in: .capsule).accessibilityElement(children: .combine)
                }
            }
        }
        if !model.agenda.isEmpty {
            heading("Traktanden")
            ForEach(Array(model.agenda.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("\(index + 1). \(item.title)").font(.headline).foregroundStyle(Color.ceviOnSurface)
                    if let text = item.text { Text(text).foregroundStyle(Color.ceviOnSurface) }
                    if let decision = item.decision { Label(decision, systemImage: "checkmark.seal").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).ceviCard().accessibilityElement(children: .combine)
            }
        }
        heading("Beschlüsse")
        if model.resolutions.isEmpty {
            Text(model.canEdit ? "Noch keine Beschlüsse. Halte fest, was ihr entschieden habt." : "Noch keine Beschlüsse.").foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        ForEach(model.resolutions) { resolution in
            Button { if model.canEdit { editing = resolution } } label: { Text(resolution.text).foregroundStyle(Color.ceviOnSurface).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).ceviCard()
                .contextMenu { if model.canEdit { Button("Löschen", systemImage: "trash", role: .destructive) { Task { await model.deleteResolution(resolution) } } } }
                .accessibilityAddTraits(model.canEdit ? .isButton : [])
        }
        if model.canEdit { Button("Beschluss hinzufügen", systemImage: "plus") { showsNew = true }.buttonStyle(.ceviText).frame(minHeight: Size.touchTarget) }
        if let file = model.minutes?.file {
            heading("Datei")
            Link(destination: file.link) { Label(file.displayName, systemImage: "doc") }.frame(minHeight: Size.touchTarget)
        }
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader).padding(.top, Spacing.s2)
    }

    /// Title, kind and date of the row; read-only text for roles that may not edit.
    @ViewBuilder private var rowCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if model.canEdit {
                TextField("Titel", text: $model.draft.title).frame(minHeight: Size.touchTarget)
                Picker("Art", selection: $model.draft.kind) {
                    ForEach([CampProtocolKind.meeting, .note, .contact, .idea], id: \.self) { Text(CampProtocolModel.kindName($0)).tag($0) }
                }
                DatePicker("Datum", selection: $model.draft.date, displayedComponents: .date)
                    .environment(\.calendar, DateFormats.calendar).environment(\.timeZone, DateFormats.timeZone)
            } else if let minutes = model.minutes {
                Text(minutes.title).font(.headline)
                Text("\(CampProtocolModel.kindName(minutes.kind)), \(CampCommsText.day(minutes.date))").foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).ceviCard()
    }

    private var saveBar: some View {
        Button("Speichern") { Task { await model.save() } }
            .buttonStyle(.ceviPrimary).disabled(!model.isDirty)
            .padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s2)
    }
}

/// Text of one resolution.
struct CampResolutionSheet: View {
    let initial: String
    let title: LocalizedStringKey
    let save: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text).scrollContentBackground(.hidden).padding(Spacing.s3)
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.sm)).padding(Spacing.s4)
                .ceviScreenBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Speichern") { save(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == initial) }
                }
                .onAppear { text = initial }
        }
    }
}

#if DEBUG
#Preview("L13 Normal") { CampCommsPreview.minutes() }
#Preview("L13 Nacht") { CampCommsPreview.minutes().preferredColorScheme(.dark) }
#Preview("L13 Laden") { CampCommsPreview.minutes(phase: .loading) }
#Preview("L13 Fehler") { CampCommsPreview.minutes(phase: .failed(state: nil, text: "x")) }
#Preview("L13 Fehler beim Speichern") { CampCommsPreview.minutes(saveFailed: true) }
#Preview("L13 Konflikt") { CampCommsPreview.minutesConflict() }
#Preview("L13 Ohne Netz") { CampCommsPreview.minutes(offline: true) }
#Preview("L13 Lager abgeschlossen") { CampCommsPreview.minutes(status: "abgeschlossen") }
#Preview("L13 Ohne Recht (Lesen)") { CampCommsPreview.minutes(role: .readOnly) }
#Preview("L13 Textgrösse AX3") { CampCommsPreview.minutes().dynamicTypeSize(.accessibility3) }
#endif
