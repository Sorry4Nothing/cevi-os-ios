import SwiftUI

/// L7: one task. Buttons appear only if the role may use them.
struct CampTaskDetailView: View {
    @State private var model: CampTaskDetailModel
    let openPortfolio: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsDue = false
    @State private var showsNote = false
    @State private var showsSort = false
    @State private var confirmsDelete = false
    @State private var newItem = ""
    @FocusState private var newItemFocused: Bool

    init(active: ActiveCamp, personId: UUID, taskId: UUID, task: CampTask?, openPortfolio: @escaping (UUID) -> Void = { _ in }) {
        _model = State(initialValue: CampTaskDetailModel(active: active, personId: personId, taskId: taskId, task: task))
        self.openPortfolio = openPortfolio
    }

    /// For previews.
    init(model: CampTaskDetailModel) {
        _model = State(initialValue: model)
        openPortfolio = { _ in }
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading: LoadingView(label: "Aufgabe wird geladen")
            case .failed(let state, _):
                if let state, state.isFullScreen, state != .offline {
                    CampStateView(state: state, notFoundMessage: "Diese Aufgabe gibt es nicht mehr. Vielleicht wurde sie gelöscht.",
                                  back: .init(title: "Zu den Aufgaben") { dismiss() }) { Task { await model.load() } }
                } else {
                    StateView.failure(retry: { Task { await model.load() } }, back: .init(title: "Zu den Aufgaben") { dismiss() })
                }
            case .loaded: if let task = model.task { detail(task) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .toolbar {
            if let task = model.task, model.phase == .loaded {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.canEdit {
                        Button { Task { await model.toggleStar() } } label: { Image(systemName: task.starred ? "star.fill" : "star") }
                            .accessibilityLabel(Text(task.starred ? "Stern entfernen" : "Stern setzen"))
                    } else if task.starred {
                        Image(systemName: "star.fill").accessibilityLabel(Text("Mit Stern"))
                    }
                }
                if model.rights.canDelete {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu { Button("Aufgabe löschen", systemImage: "trash", role: .destructive) { confirmsDelete = true } } label: { Image(systemName: "ellipsis") }
                            .accessibilityLabel(Text("Weitere Aktionen"))
                    }
                }
            }
        }
        .sheet(item: $model.conflict) { conflict in
            CampConflictView(title: String(localized: "Jemand hat diese Aufgabe gerade geändert."), subject: conflict.subject,
                             mineAuthor: String(localized: "Du, eben jetzt"), currentAuthor: String(localized: "Aktuelle Fassung"), fields: conflict.fields) { choice in
                Task { await model.resolveConflict(choice) }
            }
        }
        .sheet(isPresented: $showsDue) {
            CampDateSheet(title: String(localized: "Frist"), initial: model.task?.due ?? model.now(), allowsClear: true) { date in Task { await model.setDue(date) } }
        }
        .sheet(isPresented: $showsNote) { CampNoteSheet(title: String(localized: "Notiz"), initial: model.task?.note ?? "") { text in Task { await model.setNote(text) } } }
        .sheet(isPresented: $showsSort) { sortSheet }
        .confirmationDialog("Aufgabe löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { if await model.delete() { dismiss() } } }
        } message: { Text("Die Aufgabe verschwindet für alle.") }
    }

    private func detail(_ task: CampTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(task.title).font(.title(.largeTitle)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                    Text(subtitle(task)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                CampBannerStack()
                if let reason = model.readOnlyReason {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Label("Nur lesen.", systemImage: "lock.fill").font(.headline)
                        Text(reason).font(.subheadline)
                    }
                    .foregroundStyle(Color.ceviOnSecondaryContainer).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4).background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
                    .accessibilityElement(children: .combine)
                }
                if let error = model.error { ErrorRow(text: error) }
                if let input = model.inputError {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Label("Prüfe deine Eingabe.", systemImage: "exclamationmark.triangle.fill").font(.headline)
                        Text(input).font(.subheadline)
                    }
                    .foregroundStyle(Color.ceviOnErrorContainer).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4).background(Color.ceviErrorContainer, in: Radius.shape(Radius.md))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
                }
                if model.canSetStatus { statusChips(task) }
                facts(task)
                checklist
                links
                note(task)
                historySection
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
        .ceviScreenBackground()
        .safeAreaInset(edge: .bottom) {
            if model.canSetStatus {
                Button { Task { await model.setStatus(task.status == .done ? .open : .done) } } label: {
                    Label(task.status == .done ? "Wieder öffnen" : "Erledigt", systemImage: task.status == .done ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(.ceviPrimary).padding(Spacing.s4).background(.bar)
            }
        }
    }

    private func subtitle(_ task: CampTask) -> String {
        [task.portfolio?.name, task.due.map { String(localized: "Frist \(CampTaskText.day($0))") }].compactMap { $0 }.joined(separator: ", ")
    }

    private func statusChips(_ task: CampTask) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                ForEach(CampTaskText.boardStatuses, id: \.self) { status in
                    let selected = task.status == status
                    Button { Task { await model.setStatus(status) } } label: {
                        HStack(spacing: Spacing.s1) {
                            if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                            Text(CampTaskText.statusName(status))
                        }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.ceviSurface : Color.ceviOnSurface)
                            .padding(.horizontal, Spacing.s4).frame(minHeight: Size.touchTarget)
                            .background(selected ? Color.ceviAccent : Color.clear, in: .capsule)
                            .overlay(Capsule().stroke(Color.ceviOutline, lineWidth: selected ? 0 : Size.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func facts(_ task: CampTask) -> some View {
        VStack(spacing: 0) {
            fact("Verantwortlich") { Text(CampTaskText.person(task.responsible) ?? String(localized: "Niemand")) }
            Divider()
            fact("Unterstützung") {
                Text(task.supporters.isEmpty ? String(localized: "Niemand") : task.supporters.compactMap { CampTaskText.personName(name: $0.name, ceviName: $0.ceviName) }.joined(separator: ", "))
            }
            Divider()
            fact("Frist") {
                HStack {
                    if let hint = CampTaskText.dueHint(task, today: model.now()), hint.isOverdue { CampStatusChip(text: String(localized: "Überfällig"), symbol: "exclamationmark.triangle", isWarning: true) }
                    if model.canEdit {
                        Button(task.due.map(CampTaskText.day) ?? String(localized: "Festlegen")) { showsDue = true }.buttonStyle(.ceviText)
                    } else { Text(task.due.map(CampTaskText.day) ?? String(localized: "Keine")) }
                }
            }
            Divider()
            fact("Ressort") {
                if model.canEdit && !model.portfolios.isEmpty {
                    Menu {
                        Button("Kein Ressort") { Task { await model.setPortfolio(nil) } }
                        ForEach(model.portfolios) { portfolio in Button(portfolio.name) { Task { await model.setPortfolio(portfolio) } } }
                    } label: { portfolioLabel(task) }
                } else if let portfolio = task.portfolio {
                    Button { openPortfolio(portfolio.id) } label: { portfolioLabel(task) }.buttonStyle(.plain)
                } else { Text("Keines") }
            }
            Divider()
            fact("Wiederholung") {
                if model.canEdit {
                    Menu {
                        Button("Keine") { Task { await model.setRepeat(nil) } }
                        ForEach([CampTaskRepeat.weekly, .biweekly, .monthly], id: \.self) { value in
                            Button(CampTaskText.repeatName(value)) { Task { await model.setRepeat(value) } }
                        }
                    } label: { Text(CampTaskText.repeatName(task.repeatEvery)).foregroundStyle(Color.ceviAccent).frame(minHeight: Size.touchTarget) }
                } else { Text(CampTaskText.repeatName(task.repeatEvery)) }
            }
        }
        .ceviCard(padding: Spacing.s4)
    }

    private func portfolioLabel(_ task: CampTask) -> some View {
        HStack(spacing: Spacing.s2) {
            if let portfolio = task.portfolio { CampCodeChip(code: portfolio.code); Text(portfolio.name) } else { Text("Keines") }
        }
        .foregroundStyle(model.canEdit ? Color.ceviAccent : Color.ceviOnSurface).frame(minHeight: Size.touchTarget)
    }

    private func fact(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(label).foregroundStyle(Color.ceviOnSurfaceVariant); Spacer(minLength: Spacing.s2); value() }
            VStack(alignment: .leading) { Text(label).foregroundStyle(Color.ceviOnSurfaceVariant); value() }
        }
        .font(.body).foregroundStyle(Color.ceviOnSurface).frame(minHeight: Size.touchTarget)
    }

    // MARK: Checklist, links, note, history

    private var checklist: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                Text("Checkliste, \(model.checklistDone) von \(model.checklist.count)").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.canEdit && model.checklist.count > 1 { Button("Sortieren") { showsSort = true }.buttonStyle(.ceviText) }
            }
            VStack(spacing: 0) {
                ForEach(model.checklist) { item in
                    HStack {
                        let row = HStack(spacing: Spacing.s3) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title3)
                                .foregroundStyle(item.done ? Color.ceviAccent : Color.ceviOnSurfaceVariant).accessibilityHidden(true)
                            Text(item.text).strikethrough(item.done).foregroundStyle(Color.ceviOnSurface).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: Size.touchTarget).contentShape(.rect)
                        // Read-only: plain text, not a dimmed button (a disabled button loses its contrast).
                        if model.canSetStatus {
                            Button { Task { await model.toggle(item) } } label: { row }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("\(item.text), \(item.done ? String(localized: "erledigt") : String(localized: "offen"))"))
                        } else {
                            row.accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("\(item.text), \(item.done ? String(localized: "erledigt") : String(localized: "offen"))"))
                        }
                        if model.canEdit {
                            Button("Punkt löschen", systemImage: "trash") { Task { await model.removeChecklistItem(item) } }
                                .labelStyle(.iconOnly).foregroundStyle(Color.ceviOnSurfaceVariant).frame(width: Size.touchTarget, height: Size.touchTarget).contentShape(.rect)
                        }
                    }
                    Divider()
                }
                if model.canEdit {
                    HStack {
                        TextField("Punkt hinzufügen", text: $newItem).focused($newItemFocused).submitLabel(.done)
                            .onSubmit { let text = newItem; newItem = ""; Task { await model.addChecklistItem(text) } }
                            .frame(minHeight: Size.touchTarget)
                        if !newItem.isEmpty {
                            Button("Hinzufügen", systemImage: "plus.circle.fill") { let text = newItem; newItem = ""; Task { await model.addChecklistItem(text) } }
                                .labelStyle(.iconOnly).frame(width: Size.touchTarget, height: Size.touchTarget).contentShape(.rect)
                        }
                    }
                } else if model.checklist.isEmpty {
                    Text("Keine Punkte.").foregroundStyle(Color.ceviOnSurfaceVariant).frame(minHeight: Size.touchTarget)
                }
            }
            .ceviCard(padding: Spacing.s4)
        }
    }

    @ViewBuilder private var links: some View {
        if let links = model.details?.links, !links.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Links").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(links) { link in
                        // Only web addresses open; anything else stays plain text.
                        if let url = URL(string: link.url), url.scheme == "https" {
                            Link(destination: url) { Label(link.title, systemImage: "link").frame(maxWidth: .infinity, minHeight: Size.touchTarget, alignment: .leading) }
                        } else { Text(link.title).frame(minHeight: Size.touchTarget) }
                    }
                }
                .ceviCard(padding: Spacing.s4)
            }
        }
    }

    @ViewBuilder private func note(_ task: CampTask) -> some View {
        if task.note != nil || model.canEdit {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack {
                    Text("Notiz").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if model.canEdit { Button(task.note == nil ? "Schreiben" : "Bearbeiten") { showsNote = true }.buttonStyle(.ceviText) }
                }
                if let note = task.note { Text(note).frame(maxWidth: .infinity, alignment: .leading).ceviCard(padding: Spacing.s4).foregroundStyle(Color.ceviOnSurface) }
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        if let history = model.history {
            DisclosureGroup("Verlauf") {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    if let by = history.createdBy.flatMap({ CampTaskText.personName(name: $0.name, ceviName: $0.ceviName) }) {
                        Text("Erstellt von \(by), \(history.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    ForEach(history.entries, id: \.seq) { entry in
                        Text("\(Self.kindName(entry.kind)): \(Self.objectName(entry.objectType)), \(entry.time.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Spacing.s2)
            }
            .font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
    }

    private static func kindName(_ kind: CampChangeKind) -> String {
        switch kind {
        case .new: String(localized: "Neu")
        case .changed: String(localized: "Geändert")
        case .deleted: String(localized: "Gelöscht")
        }
    }

    private static func objectName(_ type: String) -> String {
        switch type {
        case "aufgabe": String(localized: "Aufgabe")
        case "aufgabe_checkpunkt": String(localized: "Checkliste")
        case "aufgabe_link": String(localized: "Link")
        default: String(localized: "Weiteres")
        }
    }

    /// «Nach oben» and «Nach unten»: sorting without dragging.
    private var sortSheet: some View {
        NavigationStack {
            List {
                Section { ForEach(model.checklist) { item in
                    HStack {
                        Text(item.text).foregroundStyle(Color.ceviOnSurface)
                        Spacer(minLength: Spacing.s2)
                        Button("Nach oben", systemImage: "arrow.up") { Task { await model.moveChecklistItem(item, by: -1) } }
                            .labelStyle(.iconOnly).frame(width: Size.touchTarget, height: Size.touchTarget).contentShape(.rect)
                            .disabled(item == model.checklist.first)
                        Button("Nach unten", systemImage: "arrow.down") { Task { await model.moveChecklistItem(item, by: 1) } }
                            .labelStyle(.iconOnly).frame(width: Size.touchTarget, height: Size.touchTarget).contentShape(.rect)
                            .disabled(item == model.checklist.last)
                    }
                    .buttonStyle(.borderless)
                } } footer: { Text("Benutze «Nach oben» und «Nach unten».") }
            }
            .scrollContentBackground(.hidden).ceviScreenBackground()
            .navigationTitle("Checkliste sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { showsSort = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Free text in a sheet (task note, portfolio note).
struct CampNoteSheet: View {
    let title: String
    let initial: String
    let save: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, save: @escaping (String) -> Void) {
        self.title = title
        self.initial = initial
        self.save = save
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text).scrollContentBackground(.hidden).padding(Spacing.s3)
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.sm)).padding(Spacing.s4)
                .ceviScreenBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Speichern") { save(text); dismiss() }.disabled(text == initial) }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
#Preview("L7 Normal") { CampPreview.detailScreen() }
#Preview("L7 Nacht") { CampPreview.detailScreen().preferredColorScheme(.dark) }
#Preview("L7 Laden") { CampPreview.detailScreen(phase: .loading) }
#Preview("L7 Fehler") { CampPreview.detailScreen(phase: .failed(state: nil, text: "x")) }
#Preview("L7 Nicht gefunden") { CampPreview.detailScreen(phase: .failed(state: .notFound, text: "x")) }
#Preview("L7 Eingabefehler") { CampPreview.detailScreen(inputError: "Die Frist liegt vor dem Lagerbeginn. Wähle ein Datum ab 17. Juli 2027.") }
#Preview("L7 Fehler beim Speichern") { CampPreview.detailScreen(error: "Das hat nicht geklappt. Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L7 Ohne Netz") { CampPreview.detailScreen(waiting: 1) }
#Preview("L7 Nur lesen") { CampPreview.detailScreen(role: .readOnly) }
#Preview("L7 Abgeschlossen") { CampPreview.detailScreen(status: "abgeschlossen") }
#Preview("L7 Textgrösse AX3") { CampPreview.detailScreen().dynamicTypeSize(.accessibility3) }
#endif
