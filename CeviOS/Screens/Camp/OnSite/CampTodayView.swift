import SwiftUI

/// Root of L4 inside a navigation stack: creates the model for the open camp.
struct CampTodayView: View {
    let personId: UUID
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampTodayModel?

    var body: some View {
        Group { if let model { CampTodayScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampTodayModel(active: active, personId: personId)
                model = created
                await created.load()
            }
    }
}

/// L4: «Heute», the entry of the Start tab.
struct CampTodayScreen: View {
    @Bindable var model: CampTodayModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Heute wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Heute")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { emergencyButton }
    }

    @ViewBuilder private var content: some View {
        Text(model.headline).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant)
        if model.isEmpty {
            StateView(symbol: "calendar", title: "Heute nichts eingeteilt", message: "Du hast heute keinen Dienst. Schau in den Schichtplan.").frame(minHeight: 280)
        }
        ForEach(model.shifts) { shift in
            NavigationLink { CampShiftsView(personId: model.personId) } label: {
                CampOnSiteCard {
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "calendar").foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Dein Dienst").font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant)
                            Text(shift.title).font(.headline).foregroundStyle(Color.ceviOnSurface)
                        }
                        Spacer(minLength: Spacing.s2)
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Dein Dienst: \(shift.title)"))
            .accessibilityHint(Text("Öffnet den Schichtplan"))
        }
        if !model.important.isEmpty {
            CampSectionTitle("Wichtig heute")
            CampOnSiteCard {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    ForEach(model.important) { Text($0.text).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .accessibilityElement(children: .combine)
        }
        if !model.todos.isEmpty {
            CampSectionTitle("Meine To-dos")
            CampDayTodoList(model: model, today: model.today?.date ?? model.now())
        }
        if let dayId = model.dayId {
            NavigationLink { CampDayPageView(dayId: dayId, date: model.today?.date ?? model.now(), personId: model.personId) } label: {
                Label("Tagesseite", systemImage: "doc.text").frame(minHeight: Size.touchTarget)
            }
            .buttonStyle(.ceviText)
        }
    }

    /// The emergency window is one tap away on this page.
    private var emergencyButton: some View {
        NavigationLink { CampEmergencyView() } label: {
            Label("Notfall", systemImage: "cross").font(.headline).frame(maxWidth: .infinity, minHeight: Size.button)
                .foregroundStyle(Color.ceviOnErrorContainer)
                .background(Color.ceviErrorContainer, in: Radius.shape(Radius.lg))
                .overlay(Radius.shape(Radius.lg).stroke(Color.ceviOnErrorContainer, lineWidth: Size.focusBorder))
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.bottom, Spacing.s2)
        .accessibilityHint(Text("Öffnet die Notfallnummern und die Route zum Lager"))
    }
}

/// The to-dos with their circle: done ones are struck through and say so in words.
struct CampDayTodoList: View {
    let model: CampTodoModel
    let today: Date
    var canPostpone = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.todos) { task in
                row(task)
                if task.id != model.todos.last?.id { Divider().padding(.leading, Spacing.s4 + Size.touchTarget) }
            }
        }
        .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
        .overlay(Radius.shape(Radius.md).stroke(Color.ceviOutlineVariant, lineWidth: Size.border))
    }

    private func row(_ task: CampTask) -> some View {
        let done = model.isDone(task)
        let queued = model.queuedIds.contains(task.id)
        let hint = CampTaskText.dueHint(task, today: today)?.text
        let canTick = model.taskRights.canSetStatus(task)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Button { Task { await model.toggle(task) } } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title2)
                        .foregroundStyle(done ? Color.ceviAccent : Color.ceviOnSurfaceVariant)
                        .frame(width: Size.touchTarget, height: Size.touchTarget)
                }
                .buttonStyle(.plain)
                .disabled(!canTick)
                .accessibilityLabel(Text(done ? "\(task.title), erledigt" : "\(task.title), offen"))
                .accessibilityHint(Text(canTick ? (done ? "Macht die Aufgabe wieder offen" : "Hakt die Aufgabe ab") : ""))
                .accessibilityAddTraits(.isToggle)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(task.title).strikethrough(done).foregroundStyle(done ? Color.ceviOnSurfaceVariant : Color.ceviOnSurface)
                    if !done, let hint { Text(hint).font(.caption).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                Spacer(minLength: Spacing.s2)
                if queued { Label("Wartet", systemImage: "clock").font(.caption.bold()).foregroundStyle(Color.ceviOnSecondaryContainer) }
            }
            if canPostpone, !done, task.due != nil, model.taskRights.canEdit {
                Button { Task { await model.postpone(task) } } label: { Label("In den nächsten Tag schieben", systemImage: "arrow.right") }
                    .buttonStyle(.ceviText).padding(.leading, Spacing.s4 + Size.touchTarget)
            }
        }
        .padding(.horizontal, Spacing.s2)
        .frame(minHeight: Size.touchTarget + Spacing.s2)
    }
}
