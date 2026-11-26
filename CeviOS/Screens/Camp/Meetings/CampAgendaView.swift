import SwiftUI

/// L12 for one meeting; creates its model.
struct CampAgendaView: View {
    let active: ActiveCamp
    @State private var model: CampAgendaModel

    init(active: ActiveCamp, meetingId: UUID) { self.active = active; _model = State(initialValue: CampAgendaModel(active: active, meetingId: meetingId)) }
    init(model: CampAgendaModel) { active = model.active; _model = State(initialValue: model) }

    var body: some View { CampAgendaScreen(model: model).task { await model.load() } }
}

/// L12: the agenda. Order with «Nach oben» and «Nach unten» (the visible alternative to dragging), «Auf nächsten Höck» in the row menu.
struct CampAgendaScreen: View {
    @Bindable var model: CampAgendaModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CampAgendaItem?
    @State private var showsNew = false
    @State private var deleting: CampAgendaItem?
    @State private var downloader: CampDownloader

    init(model: CampAgendaModel) {
        self.model = model
        _downloader = State(initialValue: CampDownloader(active: model.active))
    }

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Traktanden werden geladen", notFound: "Diesen Hoeck gibt es nicht mehr.",
                      back: .init(title: "Zu den Hoecks") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error ?? downloader.error, notice: noticeData ?? downloadNotice, refresh: { await model.load() }) { content }
                .safeAreaInset(edge: .bottom) { if model.canEdit { CampMainAction(title: "Traktandum hinzufügen") { showsNew = true } } }
        }
        .navigationTitle("Traktanden")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.phase == .loaded {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Mehr", systemImage: "ellipsis.circle") {
                        if let id = model.meeting?.id {
                            if model.rights.seesAllMeetings { NavigationLink(value: CampMeetingRoute.mode(id)) { Label("Hoeck-Modus", systemImage: "play.circle") } }
                            if model.rights.readsProtocols { NavigationLink(value: CampMeetingRoute.minutes(id)) { Label("Protokoll", systemImage: "doc.text") } }
                            Button("Kalenderdatei herunterladen", systemImage: "arrow.down.circle") {
                                Task { await downloader.download(.meetingCalendar(id), title: String(localized: "Kalenderdatei \(model.meeting?.title ?? "Hoeck")")) }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { item in CampAgendaItemForm(model: model, item: item) { editing = nil } }
        .sheet(isPresented: $showsNew) { CampAgendaItemForm(model: model, item: nil) { showsNew = false } }
        .confirmationDialog("Traktandum löschen?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let deleting { Task { await model.delete(deleting) } } }
        }
    }

    private var downloadNotice: CampNoticeData? {
        downloader.notice.map { CampNoticeData(title: $0, dismiss: downloader.dismissNotice) }
    }

    private var noticeData: CampNoticeData? {
        model.notice.map { notice in
            CampNoticeData(title: notice.title, message: notice.message, undo: model.hasUndo ? { Task { await model.undo() } } : nil, dismiss: model.dismissNotice)
        }
    }

    @ViewBuilder private var content: some View {
        Text(model.meeting.map { "\($0.title), \(CampCommsText.meetingDate($0.date, time: nil))" } ?? "")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
        if model.canEdit, !model.waiting.isEmpty {
            Button { Task { await model.adoptWaiting() } } label: {
                Label(model.waiting.count == 1 ? "1 wartendes Traktandum übernehmen" : "\(model.waiting.count) wartende Traktanden übernehmen", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.ceviText).frame(minHeight: Size.touchTarget)
        }
        if model.items.isEmpty {
            StateView(symbol: "list.number", title: "Keine Traktanden",
                      message: model.canEdit ? "Füge ein Traktandum hinzu oder übernimm wartende." : "Für diesen Hoeck gibt es noch keine Traktanden.")
                .frame(minHeight: 280)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    row(index + 1, item)
                    if item.id != model.items.last?.id { Divider() }
                }
            }
            .ceviCard(padding: Spacing.s2)
            if model.canEdit {
                Text("Mit «Nach oben» und «Nach unten» änderst du die Reihenfolge.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
    }

    private func row(_ number: Int, _ item: CampAgendaItem) -> some View {
        HStack(spacing: Spacing.s2) {
            Text("\(number)").font(.headline).foregroundStyle(Color.ceviAccent).frame(minWidth: 24).accessibilityHidden(true)
            Button { if model.canEdit { editing = item } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).foregroundStyle(Color.ceviOnSurface).multilineTextAlignment(.leading)
                    if item.status == .discussed { Text("Besprochen").font(.caption.bold()).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: Size.touchTarget)
            }
            .buttonStyle(.plain)
            if model.canEdit {
                Button("Nach oben", systemImage: "arrow.up") { Task { await model.move(item, by: -1) } }
                    .labelStyle(.iconOnly).disabled(!model.canMove(item, by: -1)).frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
                Button("Nach unten", systemImage: "arrow.down") { Task { await model.move(item, by: 1) } }
                    .labelStyle(.iconOnly).disabled(!model.canMove(item, by: 1)).frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
                Menu("Mehr zu «\(item.title)»", systemImage: "ellipsis") {
                    Button("Auf nächsten Höck", systemImage: "arrow.uturn.forward") { Task { await model.postpone(item) } }
                    Button("Bearbeiten", systemImage: "pencil") { editing = item }
                    Button("Löschen", systemImage: "trash", role: .destructive) { deleting = item }
                }
                .labelStyle(.iconOnly).frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
            }
        }
        .foregroundStyle(Color.ceviOnSurfaceVariant)
        .padding(.horizontal, Spacing.s2)
    }
}

/// Add or edit one agenda item.
struct CampAgendaItemForm: View {
    let model: CampAgendaModel
    let item: CampAgendaItem?
    let close: () -> Void
    @State private var draft = CampAgendaModel.Draft()

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.inputError { ErrorRow(text: error).listRowBackground(Color.clear) }
                TextField("Titel", text: $draft.title)
                TextField("Text", text: $draft.text, axis: .vertical).lineLimit(2...6)
                TextField("Entscheid", text: $draft.decision, axis: .vertical).lineLimit(1...4)
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle(item == nil ? "Traktandum hinzufügen" : "Traktandum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) }
                ToolbarItem(placement: .topBarTrailing) { Button("Speichern") { Task { if await model.save(draft, item: item) { close() } } } }
            }
            .onAppear { if let item { draft = .init(title: item.title, text: item.text ?? "", decision: item.decision ?? "") } }
        }
    }
}

#if DEBUG
#Preview("L12 Normal") { CampCommsPreview.agenda() }
#Preview("L12 Nacht") { CampCommsPreview.agenda().preferredColorScheme(.dark) }
#Preview("L12 Laden") { CampCommsPreview.agenda(phase: .loading) }
#Preview("L12 Leer") { CampCommsPreview.agenda(empty: true) }
#Preview("L12 Fehler") { CampCommsPreview.agenda(phase: .failed(state: nil, text: "x")) }
#Preview("L12 Ohne Netz") { CampCommsPreview.agenda(offline: true) }
#Preview("L12 Rückgängig") { CampCommsPreview.agenda(notice: .init(title: "«Varia» ist auf dem nächsten Hoeck.", message: nil)) }
#Preview("L12 Lager abgeschlossen") { CampCommsPreview.agenda(status: "abgeschlossen") }
#Preview("L12 Ohne Recht (Lesen)") { CampCommsPreview.agenda(role: .readOnly) }
#endif
