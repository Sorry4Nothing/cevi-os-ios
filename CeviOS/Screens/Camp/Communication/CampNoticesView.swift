import SwiftUI

/// The Pinnwand tab (L16): own navigation stack, model for the open camp.
struct CampNoticesView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampNoticesModel?

    var body: some View {
        NavigationStack {
            Group { if let model { CampNoticesScreen(model: model) } else { Color.clear } }
                .campSwitcher()
        }
        .task {
            guard model == nil else { return }
            let created = CampNoticesModel(active: active)
            model = created
            await created.load()
        }
    }
}

/// L16: the notice board with important and pinned notices, time window, files as links, polls and reactions.
struct CampNoticesScreen: View {
    @Bindable var model: CampNoticesModel
    @Environment(ActiveCamp.self) private var active
    @State private var showsForm = false
    @State private var deleting: CampNotice?

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Pinnwand wird geladen", retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, refresh: { await model.load() }) { content }
                .safeAreaInset(edge: .bottom) { if model.rights.editsNotices { CampMainAction(title: "Neue Mitteilung") { showsForm = true } } }
        }
        .navigationTitle("Pinnwand")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsForm, onDismiss: { Task { await model.load() } }) { CampNoticeFormView(model: CampNoticeFormModel(active: active)) }
        .confirmationDialog("Mitteilung löschen?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let deleting { Task { await model.delete(deleting) } } }
        } message: { Text("Die Mitteilung verschwindet für alle.") }
    }

    @ViewBuilder private var content: some View {
        if model.notices.isEmpty {
            StateView(symbol: "megaphone", title: "Keine Mitteilungen",
                      message: model.rights.editsNotices ? "Schreib eine Mitteilung an alle oder an eine Gruppe." : "Hier erscheinen die Mitteilungen der Leitung.")
                .frame(minHeight: 320)
        }
        ForEach(model.sorted) { card($0) }
    }

    private func card(_ notice: CampNotice) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(notice.poll != nil ? "Umfrage: \(notice.title)" : notice.title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            let chips = chipItems(notice)
            if !chips.isEmpty { FlowLayout(spacing: Spacing.s2) { ForEach(chips, id: \.text) { CampStatusChip(text: $0.text, symbol: $0.symbol, isWarning: $0.warning) } } }
            Text(model.audience(notice)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            if !notice.text.isEmpty { Text(notice.text).foregroundStyle(Color.ceviOnSurface) }
            ForEach(notice.files) { file in
                Link(destination: file.link) { Label(file.displayName, systemImage: "doc") }.frame(minHeight: Size.touchTarget)
            }
            if let poll = notice.poll { pollView(notice, poll) }
            reactions(notice)
            ShareLink(item: [notice.title, notice.text].filter { !$0.isEmpty }.joined(separator: "\n")) { Label("Text teilen", systemImage: "square.and.arrow.up") }
                .buttonStyle(.ceviText).frame(minHeight: Size.touchTarget)
            if model.rights.editsNotices { editorActions(notice) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
    }

    private func chipItems(_ notice: CampNotice) -> [(text: String, symbol: String, warning: Bool)] {
        var items: [(String, String, Bool)] = []
        if notice.important { items.append((String(localized: "Wichtig"), "exclamationmark.triangle", true)) }
        if notice.pinned { items.append((String(localized: "Angeheftet"), "pin", false)) }
        if let state = model.windowState(notice) { items.append((state, "clock", false)) }
        return items
    }

    private func pollView(_ notice: CampNotice, _ poll: CampPoll) -> some View {
        let largest = max(poll.options.map(\.votes).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            if poll.closed { CampStatusChip(text: String(localized: "Umfrage beendet"), symbol: "lock") }
            ForEach(poll.options) { option in
                let canVote = model.rights.interacts && !poll.closed
                Button { Task { await model.vote(notice, option: option) } } label: {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        HStack(alignment: .firstTextBaseline) {
                            if canVote { Image(systemName: option.own ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.ceviAccent).accessibilityHidden(true) }
                            Text(option.text).foregroundStyle(Color.ceviOnSurface)
                            Spacer(minLength: Spacing.s2)
                            Text(CampCommsText.votes(option.votes)).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurface)
                        }
                        ProgressView(value: Double(option.votes), total: Double(largest)).tint(Color.ceviAccent).accessibilityHidden(true)
                    }
                    .frame(minHeight: Size.touchTarget).contentShape(.rect)
                }
                .buttonStyle(.plain).disabled(!canVote)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(option.text), \(CampCommsText.votes(option.votes))\(option.own ? ", deine Stimme" : "")"))
                .accessibilityAddTraits(canVote ? (option.own ? [.isButton, .isSelected] : .isButton) : [])
            }
        }
    }

    /// The reactions with their counts; the own one is marked with a check and a word.
    private func reactions(_ notice: CampNotice) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Spacing.s2, alignment: .leading)], alignment: .leading, spacing: Spacing.s2) {
            ForEach(CampReactionKey.allCases, id: \.self) { key in
                let count = notice.reactions.counts[key] ?? 0
                if model.rights.interacts || count > 0 {
                    Button { Task { await model.react(notice, key) } } label: {
                        Label("\(count)", systemImage: Self.symbol(key)).font(.subheadline)
                            .padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
                            .background(notice.reactions.own == key ? Color.ceviSecondaryContainer : Color.ceviSurfaceContainerLow, in: .capsule)
                            .overlay(Capsule().stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
                    }
                    .buttonStyle(.plain).disabled(!model.rights.interacts)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(CampNoticesModel.reactionName(key)), \(count)\(notice.reactions.own == key ? ", deine Reaktion" : "")"))
                    .accessibilityAddTraits(notice.reactions.own == key ? .isSelected : [])
                }
            }
        }
    }

    private func editorActions(_ notice: CampNotice) -> some View {
        HStack {
            Button(notice.pinned ? "Lösen" : "Anheften", systemImage: notice.pinned ? "pin.slash" : "pin") { Task { await model.setFlags(notice, pinned: !notice.pinned) } }
            Button(notice.important ? "Nicht wichtig" : "Wichtig", systemImage: "exclamationmark.triangle") { Task { await model.setFlags(notice, important: !notice.important) } }
            Button("Löschen", systemImage: "trash", role: .destructive) { deleting = notice }
        }
        .labelStyle(.titleOnly).buttonStyle(.ceviText).font(.subheadline)
    }

    private static func symbol(_ key: CampReactionKey) -> String {
        switch key {
        case .thumbsUp: "hand.thumbsup"
        case .heart: "heart"
        case .laugh: "face.smiling"
        case .surprise: "sparkles"
        case .thanks: "hands.clap"
        }
    }
}

#if DEBUG
#Preview("L16 Normal") { CampCommsPreview.notices() }
#Preview("L16 Nacht") { CampCommsPreview.notices().preferredColorScheme(.dark) }
#Preview("L16 Laden") { CampCommsPreview.notices(phase: .loading) }
#Preview("L16 Leer") { CampCommsPreview.notices(empty: true) }
#Preview("L16 Fehler") { CampCommsPreview.notices(phase: .failed(state: nil, text: "x")) }
#Preview("L16 Ohne Netz") { CampCommsPreview.notices(offline: true) }
#Preview("L16 Lager abgeschlossen") { CampCommsPreview.notices(status: "abgeschlossen") }
#Preview("L16 Team (ohne Schreibrecht)") { CampCommsPreview.notices(role: .team) }
#Preview("L16 Textgrösse AX3") { CampCommsPreview.notices().dynamicTypeSize(.accessibility3) }
#endif
