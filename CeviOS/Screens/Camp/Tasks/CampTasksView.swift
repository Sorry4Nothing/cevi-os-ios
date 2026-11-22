import SwiftUI

nonisolated enum CampTaskRoute: Hashable {
    case task(UUID)
    case portfolio(UUID)
}

/// Root of the Aufgaben tab (L5): creates the model for the open camp.
struct CampTasksView: View {
    let profile: Profile
    let goToStart: () -> Void
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampTasksModel?

    var body: some View {
        Group {
            if let model { CampTasksScreen(model: model, goToStart: goToStart) } else { Color.clear }
        }
        .task {
            guard model == nil else { return }
            let created = CampTasksModel(active: active, personId: profile.id)
            model = created
            await created.load()
        }
    }
}

/// L5 list, T1 board, T3 schedule, L9 multi-select, L8 and L10 as sheets.
struct CampTasksScreen: View {
    enum Mode: String, CaseIterable, Identifiable { case list, kanban, schedule; var id: String { rawValue } }

    @Bindable var model: CampTasksModel
    let goToStart: () -> Void
    @Environment(ActiveCamp.self) private var active
    @State private var mode: Mode
    @State private var path: [CampTaskRoute] = []
    @State private var moving: CampTask?
    @State private var showsQuickEntry = false
    @State private var showsBulkStatus = false
    @State private var showsBulkDue = false
    @State private var confirmsDelete = false
    @State private var kanbanStatus: CampTaskStatus

    init(model: CampTasksModel, goToStart: @escaping () -> Void = {}, mode: Mode = .list, column: CampTaskStatus = .open) {
        self.model = model
        self.goToStart = goToStart
        _mode = State(initialValue: mode)
        _kanbanStatus = State(initialValue: column)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(mode == .schedule ? "Zeitplan" : "Aufgaben")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { if mode != .schedule { optionsMenu } }
                }
                .campSwitcher()
                .navigationDestination(for: CampTaskRoute.self) { route in
                    switch route {
                    case .task(let id):
                        CampTaskDetailView(active: active, personId: model.personId, taskId: id, task: model.tasks.first { $0.id == id }) { path.append(.portfolio($0)) }
                    case .portfolio(let id):
                        CampPortfolioView(active: active, portfolioId: id)
                    }
                }
                .onChange(of: path) { old, new in
                    // Back from a detail: the list may be stale.
                    if new.count < old.count { Task { await model.load() } }
                }
        }
        .sheet(item: $moving) { task in
            CampStatusSheet(title: String(localized: "Verschieben nach …"),
                            subtitle: String(localized: "«\(task.title)». Du kannst die Karte auch ziehen."),
                            counts: Dictionary(uniqueKeysWithValues: CampTaskText.boardStatuses.map { ($0, model.tasks(in: $0).count) }),
                            current: task.status) { status in Task { await model.setStatus(task, to: status) } }
        }
        .sheet(isPresented: $showsBulkStatus) {
            CampStatusSheet(title: String(localized: "Status ändern"), subtitle: String(localized: "Status für \(model.selection.count) Aufgaben"),
                            counts: [:], current: nil) { status in Task { await model.setStatusOfSelection(status) } }
        }
        .sheet(isPresented: $showsBulkDue) { CampDateSheet(title: String(localized: "Frist"), initial: model.today, allowsClear: true) { date in Task { await model.setDueOfSelection(date) } } }
        .sheet(isPresented: $showsQuickEntry, onDismiss: { Task { await model.load() } }) {
            CampQuickEntryView(model: CampQuickEntryModel(active: active))
        }
        .sheet(item: $model.conflict) { conflict in
            CampConflictView(title: String(localized: "Jemand hat diese Aufgabe gerade geändert."), subject: conflict.subject,
                             mineAuthor: String(localized: "Du, eben jetzt"), currentAuthor: String(localized: "Aktuelle Fassung"), fields: conflict.fields) { choice in
                Task { await model.resolveConflict(choice) }
            }
            .presentationDetents([.large])
        }
        .confirmationDialog("\(model.selection.count) Aufgaben löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { Task { await model.deleteSelection() } }
        } message: { Text("Gelöschte Aufgaben verschwinden für alle.") }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if mode == .schedule {
            CampScheduleView(active: active) { path.append(.task($0)) }
        } else {
            switch model.phase {
            case .loading: LoadingView(label: "Aufgaben werden geladen")
            case .failed(let state, _): failure(state)
            case .loaded: loaded
            }
        }
    }

    @ViewBuilder private func failure(_ state: CampScreenState?) -> some View {
        if state == .noAccess {
            StateView(symbol: "lock", title: "Kein Zugriff", message: "Dieser Bereich ist für die Lagerleitung. Wende dich an die Lagerleitung.",
                      primary: .init(title: "Zum Start", perform: goToStart))
        } else if let state, state.isFullScreen, state != .offline {
            CampStateView(state: state, back: .init(title: "Zum Start", perform: goToStart)) { Task { await model.load() } }
        } else {
            StateView.failure { Task { await model.load() } }
        }
    }

    private var loaded: some View {
        VStack(spacing: 0) {
            if mode == .kanban { boardHeader }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    CampBannerStack()
                    messages
                    if mode == .list { tabPicker }
                    if model.isEmpty { emptyState } else if mode == .list { list } else { board }
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
        }
        .ceviScreenBackground()
        .safeAreaInset(edge: .bottom) {
            if model.isSelecting { selectionBar } else if model.rights.canCreate {
                CampNewTaskButton { showsQuickEntry = true }.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, Spacing.s4)
            }
        }
    }

    @ViewBuilder private var messages: some View {
        if let notice = model.notice {
            CampNoticeBar(title: notice.title, message: notice.message, undo: { Task { await model.undo() } }, dismiss: model.dismissNotice)
        }
        if let error = model.error { ErrorRow(text: error) }
    }

    private var tabPicker: some View {
        Picker("Gruppierung", selection: $model.tab) {
            Text("Liste").tag(CampTaskTab.list)
            Text("Meine").tag(CampTaskTab.mine)
            Text("Personen").tag(CampTaskTab.people)
            Text("Ressort").tag(CampTaskTab.portfolio)
        }
        .pickerStyle(.segmented)
        .padding(.bottom, Spacing.s2)
    }

    @ViewBuilder private var emptyState: some View {
        StateView(symbol: "checklist", title: "Noch keine Aufgaben",
                  message: "Leg die erste Aufgabe an. Sie erscheint hier für alle, die sie sehen dürfen.")
            .frame(minHeight: 320)
    }

    private var list: some View {
        let sections = model.sections
        return Group {
            if sections.isEmpty {
                VStack(spacing: Spacing.s2) {
                    Text("Keine Aufgaben für diese Auswahl.").font(.headline).foregroundStyle(Color.ceviOnSurface)
                    if model.filter.isActive { Button("Filter zurücksetzen") { model.filter = CampTaskLocalFilter() }.buttonStyle(.ceviText) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.s8)
            }
            ForEach(sections) { section in
                if section.isDone {
                    DisclosureGroup(section.title) { rows(section.tasks) }
                        .font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).padding(.vertical, Spacing.s2)
                } else {
                    Text(section.title).font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant)
                        .accessibilityAddTraits(.isHeader).padding(.top, Spacing.s2)
                    rows(section.tasks)
                }
            }
        }
    }

    private func rows(_ tasks: [CampTask]) -> some View {
        ForEach(tasks) { task in
            CampTaskRow(task: task, today: model.today, rights: model.rights, isQueued: model.queuedIds.contains(task.id),
                        isSelecting: model.isSelecting, isSelected: model.selection.contains(task.id),
                        open: { path.append(.task(task.id)) },
                        toggleDone: { Task { await model.toggleDone(task) } },
                        move: { moving = task },
                        toggleStar: { Task { await model.toggleStar(task) } },
                        select: { model.isSelecting ? model.toggleSelection(task) : model.startSelecting(task) },
                        openPortfolio: { path.append(.portfolio($0)) })
        }
    }

    // MARK: Board (T1)

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s2) {
                    Menu {
                        Picker("Ressort", selection: $model.filter.portfolioId) {
                            Text("Alle Ressorts").tag(UUID?.none)
                            ForEach(model.portfolios) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    } label: { filterLabel(model.portfolios.first { $0.id == model.filter.portfolioId }?.name ?? String(localized: "Alle Ressorts")) }
                    Menu {
                        Picker("Person", selection: $model.filter.responsibleId) {
                            Text("Alle Personen").tag(UUID?.none)
                            ForEach(model.responsibles) { Text(CampTaskText.person($0) ?? "").tag(UUID?.some($0.id)) }
                        }
                    } label: { filterLabel(model.responsibles.first { $0.id == model.filter.responsibleId }.flatMap(CampTaskText.person) ?? String(localized: "Alle Personen")) }
                    if model.rights.canEdit && !model.isSelecting {
                        Button("Auswählen") { model.startSelecting() }.buttonStyle(.ceviText).frame(minHeight: Size.touchTarget)
                    }
                }
                .padding(.horizontal, Spacing.s4)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s2) {
                    ForEach(CampTaskText.boardStatuses, id: \.self) { status in
                        let count = model.tasks(in: status).count
                        Button { withAnimation { kanbanStatus = status } } label: {
                            Text("\(CampTaskText.statusName(status)) \(count)").font(.subheadline.weight(.semibold))
                                .foregroundStyle(kanbanStatus == status ? Color.ceviOnPrimary : Color.ceviOnSurface)
                                .padding(.horizontal, Spacing.s4).frame(minHeight: Size.touchTarget)
                                .background(kanbanStatus == status ? Color.ceviSwitchOn : Color.ceviSurfaceContainerHigh, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(CampTaskText.statusName(status)), \(count) Aufgaben"))
                        .accessibilityAddTraits(kanbanStatus == status ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Spacing.s4)
            }
        }
        .padding(.vertical, Spacing.s2)
    }

    private func filterLabel(_ text: String) -> some View {
        Label(text, systemImage: "chevron.down").labelStyle(.titleAndIcon).font(.subheadline)
            .foregroundStyle(Color.ceviOnSurface).padding(.horizontal, Spacing.s3).frame(minHeight: Size.touchTarget)
            .overlay(Capsule().stroke(Color.ceviOutline, lineWidth: Size.border))
    }

    /// One column at a time; swiping in the list below is not needed, the chips above switch the column.
    private var board: some View {
        let column = model.tasks(in: kanbanStatus)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            if column.isEmpty {
                VStack(spacing: Spacing.s1) {
                    Text("Keine Aufgaben in dieser Spalte").font(.headline).foregroundStyle(Color.ceviOnSurface)
                    Text("Verschiebe eine Aufgabe hierher mit «Verschieben nach».").foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, Spacing.s8)
            } else {
                rows(column)
            }
            Text("Wischen wechselt die Spalte. Verschieben geht über das Menü der Karte.").font(.footnote)
                .foregroundStyle(Color.ceviOnSurfaceVariant).padding(.top, Spacing.s2)
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            let all = CampTaskText.boardStatuses
            guard let index = all.firstIndex(of: kanbanStatus) else { return }
            let next = index + (value.translation.width < 0 ? 1 : -1)
            if all.indices.contains(next) { withAnimation { kanbanStatus = all[next] } }
        })
    }

    // MARK: Menu and selection bar

    private var optionsMenu: some View {
        Menu {
            Picker("Ansicht", selection: $mode) {
                Label("Liste", systemImage: "list.bullet").tag(Mode.list)
                Label("Kanban", systemImage: "rectangle.split.3x1").tag(Mode.kanban)
                Label("Zeitplan", systemImage: "calendar").tag(Mode.schedule)
            }
            Picker("Sortieren", selection: $model.sort) {
                Text("Nach Frist").tag(CampTaskSort.due)
                Text("Nach Titel").tag(CampTaskSort.title)
                Text("Von Hand").tag(CampTaskSort.manual)
            }
            Section("Filter") {
                Toggle("Nur Überfällige", isOn: $model.filter.overdueOnly)
                Toggle("Nur mit Stern", isOn: $model.filter.starredOnly)
                Picker("Status", selection: $model.filter.status) {
                    Text("Alle Status").tag(CampTaskStatus?.none)
                    ForEach(CampTaskText.boardStatuses, id: \.self) { Text(CampTaskText.statusName($0)).tag(CampTaskStatus?.some($0)) }
                }
                if !model.portfolios.isEmpty {
                    Picker("Ressort", selection: $model.filter.portfolioId) {
                        Text("Alle Ressorts").tag(UUID?.none)
                        ForEach(model.portfolios) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                if model.filter.isActive { Button("Filter zurücksetzen", systemImage: "xmark.circle") { model.filter = CampTaskLocalFilter() } }
            }
            if model.rights.canEdit, !model.isSelecting { Button("Auswählen", systemImage: "checkmark.circle") { model.startSelecting() } }
        } label: {
            Image(systemName: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
        }
        .accessibilityLabel(Text(model.filter.isActive ? "Ansicht, Sortierung und Filter, Filter aktiv" : "Ansicht, Sortierung und Filter"))
    }

    /// L9: acts on the chosen tasks. Only what the role may do.
    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                Text("\(model.selection.count) gewählt").font(.headline).foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                Button("Abbrechen") { model.stopSelecting() }.buttonStyle(.ceviText)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s2) {
                    Button("Fertig", systemImage: "checkmark") { Task { await model.setStatusOfSelection(.done) } }.buttonStyle(CeviPrimaryButtonStyle(expands: false))
                    barButton("Status", "arrow.left.arrow.right") { showsBulkStatus = true }
                    if model.rights.canEdit {
                        barButton("Frist", "calendar") { showsBulkDue = true }
                        Menu {
                            Button("Kein Ressort") { Task { await model.setPortfolioOfSelection(nil) } }
                            ForEach(model.portfolios) { portfolio in Button(portfolio.name) { Task { await model.setPortfolioOfSelection(portfolio.id) } } }
                        } label: { barLabel("Ressort", "folder") }
                    }
                    if model.rights.canDelete { barButton("Löschen", "trash") { confirmsDelete = true } }
                }
            }
        }
        .disabled(model.selection.isEmpty)
        .padding(Spacing.s4)
        .background(.bar)
    }

    private func barButton(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func barLabel(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
            .padding(.horizontal, Spacing.s4).frame(minHeight: Size.touchTarget)
            .background(Color.ceviSurfaceContainerHigh, in: .capsule)
    }
}

/// A day, with «Frist entfernen» if the field may be empty.
struct CampDateSheet: View {
    let title: String
    let initial: Date
    var allowsClear = false
    let apply: (Date?) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: Date, allowsClear: Bool = false, apply: @escaping (Date?) -> Void) {
        self.title = title
        self.initial = initial
        self.allowsClear = allowsClear
        self.apply = apply
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s3) {
                DatePicker(title, selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                    .environment(\.calendar, DateFormats.calendar).environment(\.timeZone, DateFormats.timeZone)
                Button("Übernehmen") { apply(date); dismiss() }.buttonStyle(.ceviPrimary)
                if allowsClear { Button("Frist entfernen") { apply(nil); dismiss() }.buttonStyle(.ceviText) }
                Spacer(minLength: 0)
            }
            .padding(Spacing.s4)
            .ceviScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schliessen", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

#if DEBUG
#Preview("L5 Normal") { CampPreview.tasksScreen() }
#Preview("L5 Nacht") { CampPreview.tasksScreen().preferredColorScheme(.dark) }
#Preview("L5 Laden") { CampPreview.tasksScreen(phase: .loading) }
#Preview("L5 Leer") { CampPreview.tasksScreen(tasks: []) }
#Preview("L5 Fehler") { CampPreview.tasksScreen(phase: .failed(state: nil, text: "x")) }
#Preview("L5 Kein Zugriff") { CampPreview.tasksScreen(phase: .failed(state: .noAccess, text: "x")) }
#Preview("L5 Ohne Netz") { CampPreview.tasksScreen(waiting: 3, offline: true) }
#Preview("L5 Rückgängig") {
    CampPreview.tasksScreen(notice: .init(title: "Aufgabe erledigt.", message: "«Packliste prüfen» steht jetzt unter Erledigt."))
}
#Preview("L5 Abgeschlossen") { CampPreview.tasksScreen(status: "abgeschlossen") }
#Preview("L9 Mehrfachauswahl") { CampPreview.tasksScreen(selecting: true) }
#Preview("L9 Mehrfachauswahl Nacht") { CampPreview.tasksScreen(selecting: true).preferredColorScheme(.dark) }
#Preview("T1 Kanban") { CampPreview.tasksScreen(mode: .kanban) }
#Preview("T1 Kanban Nacht") { CampPreview.tasksScreen(mode: .kanban).preferredColorScheme(.dark) }
#Preview("T1 Kanban Leer") { CampPreview.tasksScreen(tasks: [CampPreview.tasks[0]], mode: .kanban, column: .waiting) }
#Preview("T1 Kanban Abgeschlossen") { CampPreview.tasksScreen(status: "abgeschlossen", mode: .kanban) }
#Preview("T1 Kanban Ohne Netz") { CampPreview.tasksScreen(waiting: 1, offline: true, mode: .kanban) }
#Preview("L5 Textgrösse AX3") { CampPreview.tasksScreen().dynamicTypeSize(.accessibility3) }
#endif
