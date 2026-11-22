import SwiftUI

/// T3: schedule by week and month calendar. Part of the Aufgaben tab («Ansicht»).
struct CampScheduleView: View {
    @State private var model: CampScheduleModel
    let openTask: (UUID) -> Void

    init(active: ActiveCamp, openTask: @escaping (UUID) -> Void = { _ in }) {
        _model = State(initialValue: CampScheduleModel(active: active))
        self.openTask = openTask
    }

    init(model: CampScheduleModel) {
        _model = State(initialValue: model)
        openTask = { _ in }
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading: LoadingView(label: "Zeitplan wird geladen")
            case .failed(let state, _):
                if let state, state.isFullScreen, state != .offline {
                    CampStateView(state: state) { Task { await model.load() } }
                } else { StateView.failure { Task { await model.load() } } }
            case .loaded: loaded
            }
        }
        .task { await model.load() }
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text(model.active.title).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                CampBannerStack(staleSince: model.isOffline ? model.loadedAt : nil)
                Picker("Darstellung", selection: $model.tab) {
                    Text("Zeitplan").tag(CampScheduleModel.Tab.schedule)
                    Text("Kalender").tag(CampScheduleModel.Tab.calendar)
                }
                .pickerStyle(.segmented)
                if model.tab == .schedule { schedule } else { calendar }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Size.contentMax).frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
        .ceviScreenBackground()
    }

    @ViewBuilder private var schedule: some View {
        if model.isEmpty {
            StateView(symbol: "calendar", title: "Noch keine Meilensteine", message: "Aufgaben mit Frist erscheinen hier.").frame(minHeight: 320)
        }
        ForEach(model.weeks) { week in
            Text(week.title).font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityAddTraits(.isHeader).padding(.top, Spacing.s2)
            ForEach(week.items) { item in
                Button { if let id = item.taskId { openTask(id) } } label: {
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: item.kind == .milestone ? "flag" : "checkmark.circle").foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text(item.title).font(.title(.cardTitle)).foregroundStyle(Color.ceviOnSurface).multilineTextAlignment(.leading)
                            Text(item.kind == .milestone ? "Meilenstein, \(CampTaskText.day(item.date))" : "Frist, \(CampTaskText.day(item.date))")
                                .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain).disabled(item.taskId == nil).ceviCard()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var calendar: some View {
        let grid = CampScheduleBuilder.monthGrid(for: model.month)
        let items = model.items
        let days = model.schedule?.campDays ?? []
        let weekdays = [String(localized: "Mo"), String(localized: "Di"), String(localized: "Mi"), String(localized: "Do"), String(localized: "Fr"), String(localized: "Sa"), String(localized: "So")]
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                Button("Vorheriger Monat", systemImage: "chevron.left") { model.shiftMonth(by: -1) }.labelStyle(.iconOnly).frame(width: Size.touchTarget, height: Size.touchTarget)
                Spacer()
                Text(model.month.formatted(Date.FormatStyle(locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone).month(.wide).year()))
                    .font(.title(.title2)).foregroundStyle(Color.ceviOnSurface).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Nächster Monat", systemImage: "chevron.right") { model.shiftMonth(by: 1) }.labelStyle(.iconOnly).frame(width: Size.touchTarget, height: Size.touchTarget)
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { ForEach(weekdays, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).frame(maxWidth: .infinity) } }
                    .accessibilityHidden(true)
                ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                    GridRow { ForEach(Array(week.enumerated()), id: \.offset) { _, day in cell(day, items: items, campDays: days) } }
                }
            }
            Text("M Meilenstein, F Frist, L Lagertag").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
        .ceviCard()
    }

    @ViewBuilder private func cell(_ day: Date?, items: [CampScheduleItem], campDays: [CampDay]) -> some View {
        if let day {
            let marks = CampScheduleBuilder.marks(on: day, items: items, campDays: campDays)
            let number = DateFormats.calendar.component(.day, from: day)
            VStack(spacing: 2) {
                Text("\(number)").font(.subheadline).foregroundStyle(Color.ceviOnSurface)
                Text(marks.map(\.letter).joined()).font(.caption2.bold()).foregroundStyle(Color.ceviOnSecondaryContainer).frame(minHeight: 14)
            }
            .frame(maxWidth: .infinity, minHeight: Size.touchTarget)
            .background(marks.isEmpty ? Color.clear : Color.ceviSecondaryContainer, in: Radius.shape(8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(CampTaskText.day(day))\(marks.isEmpty ? "" : ", " + marks.map(\.name).joined(separator: ", "))"))
        } else {
            Color.clear.frame(minHeight: Size.touchTarget)
        }
    }
}

#if DEBUG
#Preview("T3 Zeitplan") { CampPreview.scheduleScreen() }
#Preview("T3 Kalender") { CampPreview.scheduleScreen(calendar: true) }
#Preview("T3 Kalender Nacht") { CampPreview.scheduleScreen(calendar: true).preferredColorScheme(.dark) }
#Preview("T3 Laden") { CampPreview.scheduleScreen(phase: .loading) }
#Preview("T3 Leer") { CampPreview.scheduleScreen(empty: true) }
#Preview("T3 Fehler") { CampPreview.scheduleScreen(phase: .failed(state: nil, text: "x")) }
#Preview("T3 Ohne Netz") { CampPreview.scheduleScreen(calendar: true, offline: true, waiting: 1) }
#Preview("T3 Textgrösse AX3") { CampPreview.scheduleScreen().dynamicTypeSize(.accessibility3) }
#endif
