import SwiftUI

/// Root of the Start tab: L2 for leads, L3 for the team.
struct CampStartView: View {
    let profile: Profile
    let openTasks: () -> Void
    @Environment(ActiveCamp.self) private var active
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CampStartModel?

    var body: some View {
        Group {
            if let model { CampStartScreen(model: model, personId: profile.id, openTasks: openTasks) } else { Color.clear }
        }
        .task {
            guard model == nil else { return }
            let created = CampStartModel(active: active)
            model = created
            await created.load()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await active.refreshQueue()
        }
    }
}

struct CampStartScreen: View {
    let model: CampStartModel
    let personId: UUID
    var openTasks: () -> Void = {}
    @Environment(ActiveCamp.self) private var active
    @State private var path: [CampTaskRoute] = []
    @State private var showsQuickEntry = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(active.title)
                .navigationBarTitleDisplayMode(.large)
                .campSwitcher()
                .navigationDestination(for: CampTaskRoute.self) { route in
                    switch route {
                    case .task(let id): CampTaskDetailView(active: active, personId: personId, taskId: id, task: model.ownTasks.first { $0.id == id }) { path.append(.portfolio($0)) }
                    case .portfolio(let id): CampPortfolioView(active: active, portfolioId: id)
                    }
                }
        }
        .sheet(isPresented: $showsQuickEntry, onDismiss: { Task { await model.load() } }) { CampQuickEntryView(model: CampQuickEntryModel(active: active)) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading: LoadingView(label: model.isLead ? "Start wird geladen" : "Dein Bereich wird geladen")
        case .failed(let state, _):
            if let state, state.isFullScreen, state != .offline { CampStateView(state: state) { Task { await model.load() } } }
            else { StateView.failure { Task { await model.load() } } }
        case .loaded: loaded
        }
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                CampBannerStack(staleSince: model.isOffline ? model.loadedAt : nil)
                if !model.isLead { Text("Mein Bereich").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                countdown
                today
                if model.isLead, let warning = model.weatherWarning {
                    Label(warning, systemImage: "cloud.bolt").font(.headline).foregroundStyle(Color.ceviOnWarningContainer)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.s4)
                        .background(Color.ceviWarningContainer, in: Radius.shape(Radius.md)).accessibilityElement(children: .combine)
                }
                if model.isLead { lead } else { team }
                meeting
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax).frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
        .ceviScreenBackground()
        .safeAreaInset(edge: .bottom) {
            if model.isLead && model.canCreate {
                CampNewTaskButton(title: "Schnell erfassen") { showsQuickEntry = true }.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, Spacing.s4)
            }
        }
    }

    /// L4: «Heute» is the way in while the camp runs.
    @ViewBuilder private var today: some View {
        if model.isRunning, let camp = active.camp {
            let title = CampOnSiteText.campDay(model.now(), from: camp.from, to: camp.to)
            NavigationLink { CampTodayView(personId: personId) } label: {
                CampOnSiteCard {
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "sun.max").foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Heute").font(.headline).foregroundStyle(Color.ceviOnSurface)
                            Text(title).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                        }
                        Spacer(minLength: Spacing.s2)
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
                    }
                    .frame(minHeight: Size.touchTarget)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Heute, \(title)"))
            .accessibilityHint(Text("Öffnet deinen Tag"))
        }
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(active.isReadOnly ? String(localized: "Das Lager ist vorbei") : model.countdownTitle).font(.title(.title2)).foregroundStyle(Color.ceviOnSurface)
            if let camp = active.camp {
                Text(CampFormat.dates(from: camp.from, to: camp.to) + (camp.place.map { ", \($0)" } ?? "")).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            if model.isLead, let percent = model.percentDone, let tasks = model.start?.progress.tasks {
                ProgressView(value: Double(percent), total: 100).tint(Color.ceviSwitchOn)
                    .accessibilityLabel(Text("Fortschritt")).accessibilityValue(Text("\(percent) Prozent erledigt"))
                HStack(spacing: Spacing.s4) {
                    Text("\(percent) Prozent erledigt")
                    if tasks.overdue > 0 {
                        Button("\(tasks.overdue) überfällig", action: openTasks).buttonStyle(.ceviText)
                            .accessibilityHint(Text("Öffnet die Aufgaben"))
                    }
                }
                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).ceviCard().accessibilityElement(children: .contain)
    }

    @ViewBuilder private var lead: some View {
        if model.canCreate {
            Button { showsQuickEntry = true } label: { Label("Aufgabe", systemImage: "checkmark.circle") }.buttonStyle(.bordered).frame(minHeight: Size.touchTarget)
        }
        let tasks = model.ownTasks
        Text("Für dich").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
        if tasks.isEmpty {
            Text("Nichts Offenes für dich in den nächsten sieben Tagen.").foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        ForEach(tasks) { task in
            CampTaskRow(task: task, today: model.now(), rights: CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: personId),
                        open: { path.append(.task(task.id)) })
        }
    }

    /// L3: what is meant for the team member. Dienste and tasks come from «Meine Woche».
    @ViewBuilder private var team: some View {
        let shifts = model.shifts, tasks = model.ownTasks
        if shifts.isEmpty && tasks.isEmpty && model.nextMeeting == nil {
            StateView(symbol: "tray", title: "Noch nichts für dich", message: "Dienste, Zimmer und Fahrten erscheinen, sobald die Lagerleitung sie einteilt.").frame(minHeight: 320)
        }
        if !shifts.isEmpty {
            Text("Meine Dienste").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
            ForEach(shifts) { own in
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(own.duty?.name ?? String(localized: "Dienst")).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                    Text(CampTaskText.day(own.shift.date)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading).ceviCard().accessibilityElement(children: .combine)
            }
        }
        if !tasks.isEmpty {
            Text("Meine Aufgaben").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
            ForEach(tasks) { task in
                CampTaskRow(task: task, today: model.now(), rights: CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: personId),
                            open: { path.append(.task(task.id)) })
            }
        }
    }

    @ViewBuilder private var meeting: some View {
        if let next = model.nextMeeting {
            Text("Nächster Hoeck").font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text([CampTaskText.day(next.date), next.time].compactMap { $0 }.joined(separator: ", ")).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface)
                Text(next.title).foregroundStyle(Color.ceviOnSurface)
                if let place = next.place { Text(place).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).ceviCard().accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
#Preview("L2 Normal") { CampPreview.startScreen() }
#Preview("L2 Nacht") { CampPreview.startScreen().preferredColorScheme(.dark) }
#Preview("L2 Laden") { CampPreview.startScreen(phase: .loading) }
#Preview("L2 Fehler") { CampPreview.startScreen(phase: .failed(state: nil, text: "x")) }
#Preview("L2 Ohne Netz") { CampPreview.startScreen(waiting: 3, offline: true) }
#Preview("L2 Abgeschlossen") { CampPreview.startScreen(status: "abgeschlossen") }
#Preview("L2 Textgrösse AX3") { CampPreview.startScreen().dynamicTypeSize(.accessibility3) }
#Preview("L3 Normal") { CampPreview.startScreen(role: .team) }
#Preview("L3 Nacht") { CampPreview.startScreen(role: .team).preferredColorScheme(.dark) }
#Preview("L3 Laden") { CampPreview.startScreen(role: .team, phase: .loading) }
#Preview("L3 Leer") { CampPreview.startScreen(role: .team, empty: true) }
#Preview("L3 Fehler") { CampPreview.startScreen(role: .team, phase: .failed(state: nil, text: "x")) }
#Preview("L3 Ohne Netz") { CampPreview.startScreen(role: .team, offline: true) }
#Preview("L3 Abgeschlossen") { CampPreview.startScreen(role: .team, status: "abgeschlossen") }
#endif
