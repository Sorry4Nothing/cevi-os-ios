import SwiftUI

/// Root of L18 inside a navigation stack; creates the model.
struct CampInboxView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampInboxModel?

    var body: some View {
        Group { if let model { CampInboxScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampInboxModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L18: «Feedback und Rückfragen des Teams».
struct CampInboxScreen: View {
    @Bindable var model: CampInboxModel
    @Environment(\.dismiss) private var dismiss
    @State private var replying: CampInboxEntry?
    @State private var assigning: CampInboxEntry?
    @State private var deleting: CampInboxEntry?

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Eingang wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: notice, refresh: { await model.load() }) { content }
        }
        .navigationTitle("Eingang")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $replying) { entry in CampResolutionSheet(initial: entry.reply ?? "", title: "Antworten") { text in Task { _ = await model.reply(entry, text: text) } } }
        .confirmationDialog("Ressort zuweisen", isPresented: .init(get: { assigning != nil }, set: { if !$0 { assigning = nil } }), titleVisibility: .visible) {
            ForEach(model.portfolios) { portfolio in Button(portfolio.name) { if let assigning { Task { await model.assign(assigning, to: portfolio) } } } }
            Button("Kein Ressort") { if let assigning { Task { await model.assign(assigning, to: nil) } } }
        }
        .confirmationDialog("Eintrag löschen?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let deleting { Task { await model.delete(deleting) } } }
        } message: { Text("Gelöschte Einträge lassen sich nicht wiederherstellen.") }
    }

    private var notice: CampNoticeData? {
        model.notice.map { notice in
            CampNoticeData(title: notice.title, message: notice.message, undo: model.hasUndo ? { Task { await model.undo() } } : nil, dismiss: model.dismissNotice)
        }
    }

    @ViewBuilder private var content: some View {
        Text("Feedback und Rückfragen des Teams").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        if model.entries.isEmpty {
            StateView(symbol: "tray", title: "Eingang leer", message: "Feedback und Rückfragen des Teams erscheinen hier.").frame(minHeight: 320)
        }
        ForEach(model.sorted) { card($0) }
    }

    private func card(_ entry: CampInboxEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                Text(CampInboxModel.kindName(entry.kind)).font(.headline).foregroundStyle(Color.ceviOnSurface)
                CampStatusChip(text: CampInboxModel.statusName(entry.status), symbol: entry.status == .done ? "checkmark" : "circle.dashed", isWarning: entry.status == .new)
            }
            // Anonymous: the word, never a name.
            Text(model.sender(entry)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            Text(entry.text).foregroundStyle(Color.ceviOnSurface)
            if let portfolio = model.portfolioName(entry) { Label(portfolio, systemImage: "folder").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            if entry.agendaItemId != nil { Label("Auf dem Hoeck", systemImage: "list.number").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            if let reply = entry.reply {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Antwort").font(.caption.bold()).foregroundStyle(Color.ceviOnSurfaceVariant)
                    Text(reply).foregroundStyle(Color.ceviOnSurface)
                }
                .padding(Spacing.s3).frame(maxWidth: .infinity, alignment: .leading).background(Color.ceviSurface, in: Radius.shape(Radius.sm))
            }
            if model.canAnswer { actions(entry) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .contain)
    }

    private func actions(_ entry: CampInboxEntry) -> some View {
        FlowLayout(spacing: Spacing.s1) {
            Button("Antworten") { replying = entry }
            if !model.portfolios.isEmpty { Button("Ressort zuweisen") { assigning = entry } }
            if entry.agendaItemId == nil { Button("Als Traktandum") { Task { await model.makeAgendaItem(entry) } } }
            Menu("Status") {
                ForEach([CampInboxStatus.new, .inProgress, .done], id: \.self) { status in
                    Button(CampInboxModel.statusName(status), systemImage: entry.status == status ? "checkmark" : "") { Task { await model.setStatus(entry, status) } }
                }
            }
            Button("Löschen", role: .destructive) { deleting = entry }
        }
        .buttonStyle(.ceviText).frame(minHeight: Size.touchTarget)
    }
}

#if DEBUG
#Preview("L18 Normal") { CampCommsPreview.inbox() }
#Preview("L18 Nacht") { CampCommsPreview.inbox().preferredColorScheme(.dark) }
#Preview("L18 Laden") { CampCommsPreview.inbox(phase: .loading) }
#Preview("L18 Leer") { CampCommsPreview.inbox(empty: true) }
#Preview("L18 Fehler") { CampCommsPreview.inbox(phase: .failed(state: nil, text: "x")) }
#Preview("L18 Fehler beim Speichern") { CampCommsPreview.inbox(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L18 Rückgängig") { CampCommsPreview.inbox(notice: .init(title: "Als Traktandum übernommen.", message: "Es steht auf dem nächsten Hoeck.")) }
#Preview("L18 Lager abgeschlossen") { CampCommsPreview.inbox(status: "abgeschlossen") }
#Preview("L18 Ohne Recht (Team)") { CampCommsPreview.inbox(phase: .failed(state: .noAccess, text: ""), role: .team) }
#Preview("L18 Textgrösse AX3") { CampCommsPreview.inbox().dynamicTypeSize(.accessibility3) }
#endif
