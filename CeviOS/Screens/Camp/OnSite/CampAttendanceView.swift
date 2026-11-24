import SwiftUI

/// Root of L26 inside a navigation stack: creates the model for the open camp.
struct CampAttendanceView: View {
    let profile: Profile
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampAttendanceModel?

    var body: some View {
        Group { if let model { CampAttendanceScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampAttendanceModel(active: active, personId: profile.id, ownLabel: CampRosterText.label(name: profile.name, ceviName: profile.ceviName))
                model = created
                await created.load()
            }
    }
}

/// L26: «Anwesenheit», the whole day with one tap.
struct CampAttendanceScreen: View {
    @Bindable var model: CampAttendanceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var requestNote = ""

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Anwesenheit wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Anwesenheit")
        .navigationBarTitleDisplayMode(.large)
        .alert("Anfrage an die Lagerleitung nötig", isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.cancelRequest() } })) {
            TextField("Notiz (freiwillig)", text: $requestNote)
            Button("Abbrechen", role: .cancel) { requestNote = "" }
            Button("Anfrage senden") {
                let note = requestNote
                requestNote = ""
                Task { await model.sendRequest(note: note) }
            }
        } message: { Text(model.pending?.message ?? "") }
    }

    @ViewBuilder private var content: some View {
        if model.days.isEmpty {
            StateView(symbol: "checklist", title: "Noch keine Lagertage", message: "Die Anwesenheit erscheint, sobald die Lagerleitung den Zeitplan angelegt hat.").frame(minHeight: 320)
        } else {
            dayChips
            if !model.onSite.readsMatrix {
                CampRoleHint(title: "Du siehst deine eigene Zeile.",
                             message: model.canSet ? "Ändern kannst du nur deine Zusage." : "Ändern kannst du hier nichts.")
            }
            if let hint = model.deadlineHint { Text(hint).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
            ForEach(model.openRequests) { requestCard($0) }
            if model.rows.isEmpty {
                Text("Hier ist niemand.").foregroundStyle(Color.ceviOnSurfaceVariant).padding(.vertical, Spacing.s4)
            }
            ForEach(model.rows) { personCard($0) }
            ForEach(model.ownRequestLines, id: \.self) { Label($0, systemImage: "clock").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
        }
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                ForEach(model.days) { day in
                    let isOn = day.id == model.selectedDayId
                    Button { Task { await model.select(day.id) } } label: {
                        HStack(spacing: Spacing.s1) {
                            if isOn { Image(systemName: "checkmark").accessibilityHidden(true) }
                            Text(CampRosterText.dayChip(day.date))
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, Spacing.s4)
                        .frame(minHeight: Size.touchTarget)
                        .foregroundStyle(isOn ? Color.ceviSurface : Color.ceviOnSurface)
                        .background(isOn ? Color.ceviAccent : Color.clear, in: .capsule)
                        .overlay(Capsule().stroke(Color.ceviOutline, lineWidth: isOn ? 0 : Size.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(CampOnSiteText.dayTitle(day.date)))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func personCard(_ row: CampAttendanceModel.Row) -> some View {
        CampOnSiteCard {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).font(.headline).foregroundStyle(Color.ceviOnSurface)
                    if model.busyId == row.id { ProgressView().accessibilityLabel(Text("Wird gespeichert")) }
                    Spacer(minLength: Spacing.s2)
                    if model.canSet && !row.isWholeDayPresent {
                        Button("Ganzer Tag da") { Task { await model.setWholeDay(row) } }
                            .font(.subheadline.bold()).buttonStyle(.ceviText).frame(minHeight: Size.touchTarget)
                            .accessibilityLabel(Text("\(row.label): ganzer Tag da"))
                    }
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.s2)) : AnyLayout(HStackLayout(spacing: Spacing.s2))
                layout { ForEach(row.cells) { cell($0, of: row) } }
            }
        }
    }

    @ViewBuilder private func cell(_ cell: CampAttendanceModel.Cell, of row: CampAttendanceModel.Row) -> some View {
        let face = VStack(spacing: Spacing.s1) {
            Text(cell.name).font(.caption)
            Label(CampOnSiteText.value(cell.value), systemImage: symbol(cell.value)).font(.subheadline.bold())
            if cell.requested != nil { Text("Anfrage offen").font(.caption2) }
        }
        .foregroundStyle(foreground(cell.value))
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget + Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .background(background(cell.value), in: Radius.shape(Radius.sm))
        .overlay { if cell.value == .open { Radius.shape(Radius.sm).stroke(Color.ceviOutline, lineWidth: Size.border) } }
        let spoken = Text("\(row.label), \(cell.name): \(CampOnSiteText.value(cell.value))")
        if model.canSet {
            Menu {
                Button("Da", systemImage: "checkmark") { Task { await model.set(row, section: cell.sectionId, to: .present) } }
                Button("Frei", systemImage: "sun.max") { Task { await model.set(row, section: cell.sectionId, to: .absent) } }
            } label: { face }
                .accessibilityLabel(spoken)
                .accessibilityHint(Text("Öffnet die Auswahl Da oder Frei"))
        } else {
            face.accessibilityElement(children: .ignore).accessibilityLabel(spoken)
        }
    }

    private func requestCard(_ request: CampAttendanceModel.OpenRequest) -> some View {
        CampOnSiteCard {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Label("Anfrage", systemImage: "tray").font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurfaceVariant)
                Text(request.text).foregroundStyle(Color.ceviOnSurface).fixedSize(horizontal: false, vertical: true)
                if let note = request.note { Text("«\(note)»").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                HStack {
                    Button("Annehmen") { Task { await model.decide(request, .accepted) } }.buttonStyle(.ceviPrimary)
                    Button("Ablehnen") { Task { await model.decide(request, .rejected) } }.buttonStyle(.ceviText)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func symbol(_ value: CampAttendanceValue) -> String {
        switch value {
        case .present: "checkmark"
        case .absent: "sun.max"
        case .open: "questionmark.circle"
        }
    }

    private func foreground(_ value: CampAttendanceValue) -> Color {
        switch value {
        case .present: Color.ceviOnSuccessContainer
        case .absent: Color.ceviOnSecondaryContainer
        case .open: Color.ceviOnSurface
        }
    }

    private func background(_ value: CampAttendanceValue) -> Color {
        switch value {
        case .present: Color.ceviSuccessContainer
        case .absent: Color.ceviSecondaryContainer
        case .open: Color.clear
        }
    }
}
