import SwiftUI

/// Root of L1a inside a navigation stack.
struct CampCheckView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampCheckModel?

    var body: some View {
        Group { if let model { CampCheckScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampCheckModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L1a: «Lager-Check», built without a design draft from the existing building blocks (`docs/lager.md`).
struct CampCheckScreen: View {
    @Bindable var model: CampCheckModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsAdd = false
    @State private var renaming: CampCheckPoint?
    @State private var deleting: CampCheckPoint?

    var body: some View {
        Group {
            if let conflict = model.conflict {
                CampConflictView(title: String(localized: "Jemand hat diesen Punkt gerade geändert."), subject: conflict.current.title,
                                 mineAuthor: String(localized: "Du, eben jetzt"), currentAuthor: String(localized: "Aktuelle Fassung"), fields: conflict.fields) { choice in
                    Task { await model.resolve(choice) }
                }
            } else {
                CampPhaseView(phase: model.phase, loading: "Lager-Check wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
                    CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
                }
            }
        }
        .navigationTitle("Lager-Check")
        .navigationSubtitle("Sind wir bereit?")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if model.canAddPoint && model.phase == .loaded && model.conflict == nil { CampMainAction(title: "Punkt hinzufügen") { showsAdd = true } }
        }
        .sheet(isPresented: $showsAdd) {
            CampCheckPointSheet(title: "Punkt hinzufügen", initial: "", error: model.error, save: { await model.add(title: $0) }) { showsAdd = false }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $renaming) { point in
            CampCheckPointSheet(title: "Punkt umbenennen", initial: point.title, error: model.error, save: { await model.rename(point, to: $0) }) { renaming = nil }
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Punkt löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { point in
            Button("Löschen", role: .destructive) { Task { await model.delete(point) } }
        } message: { point in
            Text("«\(point.title)» wird gelöscht.")
        }
    }

    @ViewBuilder private var content: some View {
        if model.canRetry {
            Button("Nochmals versuchen", systemImage: "arrow.clockwise") { Task { await model.retry() } }.buttonStyle(.ceviText)
        }
        if let check = model.check {
            summary(check)
            ForEach(check.checkers) { checker in checkerCard(checker) }
        }
        CampSectionTitle("Eigene Punkte")
        ownPoints
    }

    // MARK: Overall state and checkers

    private func summary(_ check: CampCheck) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            CampCheckStateChip(state: check.state)
            Text(CampCheckModel.headline(check.state)).font(.title(.title2)).foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
            Text("Stand vom \(CampCommsText.day(check.date))").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .combine)
    }

    private func checkerCard(_ checker: CampChecker) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Text(checker.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s2)
                CampCheckStateChip(state: checker.state)
            }
            .fixedSize(horizontal: false, vertical: true)
            if checker.notes.isEmpty {
                Text("Nichts zu tun.").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            ForEach(Array(checker.notes.enumerated()), id: \.offset) { _, note in noteView(note) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .contain)
    }

    private func noteView(_ note: CampCheckNote) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Label {
                Text(note.text).foregroundStyle(Color.ceviOnSurface)
            } icon: {
                Image(systemName: note.severity == .open ? "exclamationmark.circle.fill" : "info.circle").foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            .labelStyle(.titleAndIcon)
            ForEach(note.examples) { example in
                let detail = CampCheckModel.detail(example)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    Text(example.title).font(.subheadline).foregroundStyle(Color.ceviOnSurface)
                    Spacer(minLength: Spacing.s2)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                .padding(.leading, Spacing.s6)
                .accessibilityElement(children: .combine)
            }
            if let count = note.count, count > note.examples.count, !note.examples.isEmpty {
                Text("und \(count - note.examples.count) weitere").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant).padding(.leading, Spacing.s6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spoken(note)))
    }

    private func spoken(_ note: CampCheckNote) -> String {
        var parts = [note.severity == .open ? String(localized: "Offen") : String(localized: "Hinweis"), note.text]
        parts += note.examples.map { [$0.title, CampCheckModel.detail($0)].compactMap { $0 }.joined(separator: ", ") }
        return parts.joined(separator: ". ")
    }

    // MARK: Own points

    @ViewBuilder private var ownPoints: some View {
        if model.points.isEmpty {
            StateView(symbol: "checklist", title: "Noch keine eigenen Punkte",
                      message: model.canEdit ? "Halte hier fest, was ihr sonst noch klären wollt." : "Hier erscheinen die Punkte der Lagerleitung.").frame(minHeight: 240)
        } else {
            VStack(spacing: 0) {
                ForEach(model.points) { point in
                    row(point)
                    if point.id != model.points.last?.id { Divider().padding(.leading, Spacing.s4 + Size.touchTarget) }
                }
            }
            .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
            .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
        }
    }

    private func row(_ point: CampCheckPoint) -> some View {
        let state = point.done ? String(localized: "erledigt") : String(localized: "offen")
        let label = HStack(spacing: Spacing.s3) {
            Image(systemName: point.done ? "checkmark.circle.fill" : "circle").font(.title2)
                .foregroundStyle(point.done ? Color.ceviAccent : Color.ceviOnSurfaceVariant).accessibilityHidden(true)
            Text(point.title).strikethrough(point.done).foregroundStyle(point.done ? Color.ceviOnSurfaceVariant : Color.ceviOnSurface)
            Spacer(minLength: Spacing.s2)
        }
        .padding(.leading, Spacing.s4)
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget + Spacing.s3, alignment: .leading)
        .contentShape(.rect)
        return HStack(spacing: 0) {
            if model.canEdit {
                Button { Task { await model.toggle(point) } } label: { label }.buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(point.title), \(state)"))
                    .accessibilityAddTraits(.isToggle)
                Menu {
                    Button("Umbenennen", systemImage: "pencil") { renaming = point }
                    Button("Löschen", systemImage: "trash", role: .destructive) { deleting = point }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Color.ceviOnSurfaceVariant).frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
                }
                .accessibilityLabel(Text("Mehr zu \(point.title)"))
            } else {
                label.accessibilityElement(children: .ignore).accessibilityLabel(Text("\(point.title), \(state)"))
            }
        }
    }
}

/// «Bereit», «Hinweise» or «Offen»: a word and a symbol, never color alone.
struct CampCheckStateChip: View {
    let state: CampCheckState

    var body: some View {
        Label(CampCheckModel.stateName(state), systemImage: symbol)
            .font(.subheadline.bold())
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
    }

    private var symbol: String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .notes: "info.circle.fill"
        case .open: "exclamationmark.triangle.fill"
        }
    }

    private var foreground: Color {
        switch state {
        case .ready: .ceviOnSuccessContainer
        case .notes: .ceviOnWarningContainer
        case .open: .ceviOnErrorContainer
        }
    }

    private var background: Color {
        switch state {
        case .ready: .ceviSuccessContainer
        case .notes: .ceviWarningContainer
        case .open: .ceviErrorContainer
        }
    }
}

/// One text field for adding and renaming. Stays open while the write fails; the message and the retry are on the screen behind.
struct CampCheckPointSheet: View {
    let title: LocalizedStringKey
    let initial: String
    let error: String?
    let save: (String) async -> Bool
    let close: () -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let error { ErrorRow(text: error) }
                    Text("Punkt").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    TextField("Punkt", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).frame(minHeight: Size.field)
                        .onChange(of: text) { _, value in if value.count > CampCheckModel.maxTitle { text = String(value.prefix(CampCheckModel.maxTitle)) } }
                    Button("Speichern") { Task { if await save(text) { close() } } }.buttonStyle(.ceviPrimary)
                }
                .padding(Spacing.s4)
            }
            .ceviScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark", action: close) } }
            .onAppear { text = initial }
        }
    }
}
