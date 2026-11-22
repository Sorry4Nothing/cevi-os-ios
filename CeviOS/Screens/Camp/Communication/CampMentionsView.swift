import SwiftUI

/// Root of L15 inside a navigation stack; creates the model.
struct CampMentionsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampMentionsModel?

    var body: some View {
        Group { if let model { CampMentionsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampMentionsModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L15: «Stellen, an denen du erwähnt wirst».
struct CampMentionsScreen: View {
    @Bindable var model: CampMentionsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Erwähnungen werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: notice, refresh: { await model.load() }) { content }
        }
        .navigationTitle("Erwähnungen")
        .navigationBarTitleDisplayMode(.large)
    }

    private var notice: CampNoticeData? {
        model.notice.map { CampNoticeData(title: $0.title, message: $0.message, undo: nil, dismiss: model.dismissNotice) }
    }

    @ViewBuilder private var content: some View {
        Text("Stellen, an denen du erwähnt wirst").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        if model.mentions.isEmpty {
            StateView(symbol: "at", title: "Keine Erwähnungen", message: "Hier erscheinen Stellen, an denen jemand dich erwähnt.").frame(minHeight: 320)
        }
        ForEach(model.open) { card($0) }
        if !model.done.isEmpty {
            DisclosureGroup(model.done.count == 1 ? "Erledigt, 1 Erwähnung" : "Erledigt, \(model.done.count) Erwähnungen") {
                ForEach(model.done) { card($0) }
            }
            .font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).padding(.vertical, Spacing.s2)
        }
    }

    private func card(_ mention: CampMention) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(model.caption(mention)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            Text(mention.title).foregroundStyle(Color.ceviOnSurface)
            if mention.done { CampStatusChip(text: String(localized: "Erledigt"), symbol: "checkmark") }
            if mention.taskId != nil { CampStatusChip(text: String(localized: "Aufgabe angelegt"), symbol: "checklist") }
            if model.canWrite {
                HStack {
                    if mention.taskId == nil, !mention.done { Button("Als Aufgabe") { Task { await model.makeTask(mention) } }.buttonStyle(.ceviText) }
                    Button(mention.done ? "Wieder öffnen" : "Erledigt") { Task { await model.setDone(mention, !mention.done) } }.buttonStyle(.ceviText)
                }
                .frame(minHeight: Size.touchTarget)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).ceviCard()
    }
}

#if DEBUG
#Preview("L15 Normal") { CampCommsPreview.mentions() }
#Preview("L15 Nacht") { CampCommsPreview.mentions().preferredColorScheme(.dark) }
#Preview("L15 Laden") { CampCommsPreview.mentions(phase: .loading) }
#Preview("L15 Leer") { CampCommsPreview.mentions(empty: true) }
#Preview("L15 Fehler") { CampCommsPreview.mentions(phase: .failed(state: nil, text: "x")) }
#Preview("L15 Rückgängig") { CampCommsPreview.mentions(notice: .init(title: "Als Aufgabe angelegt.", message: "«Offerte nachfragen» steht jetzt in deinen Aufgaben.")) }
#Preview("L15 Lager abgeschlossen") { CampCommsPreview.mentions(status: "abgeschlossen") }
#Preview("L15 Textgrösse AX3") { CampCommsPreview.mentions().dynamicTypeSize(.accessibility3) }
#endif
