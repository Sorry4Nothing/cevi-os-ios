import SwiftUI

/// Root of T2 inside a navigation stack: creates the model for the open camp.
struct CampShiftsView: View {
    let personId: UUID
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampShiftsModel?

    var body: some View {
        Group { if let model { CampShiftsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampShiftsModel(active: active, personId: personId)
                model = created
                await created.load()
            }
    }
}

/// T2: «Schichtplan», a list per day with the duties and the people on them.
struct CampShiftsScreen: View {
    @Bindable var model: CampShiftsModel
    @Environment(\.dismiss) private var dismiss
    @State private var picking: CampShiftsModel.DutyRow?
    @State private var showsProposal = false
    @State private var showsStatistics = false
    @State private var showsDutyForm = false

    var body: some View {
        CampPhaseView(phase: model.phase, loading: "Schichtplan wird geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
            CampScroll(staleSince: model.staleSince, error: model.error, notice: model.noticeData(), refresh: { await model.load() }) { content }
        }
        .navigationTitle("Schichtplan")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.phase == .loaded, !model.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Verteilung", systemImage: "person.2") { showsStatistics = true } }
            }
        }
        .sheet(item: $picking) { row in
            CampPersonPicker(title: "Person wählen", confirmTitle: "Einteilen", model: model, confirm: { people in
                picking = nil
                if let day = model.selectedDay { Task { await model.add(people, to: row, day: day) } }
            }, close: { picking = nil })
        }
        .sheet(isPresented: $showsProposal, onDismiss: model.cancelProposal) { CampShiftProposalSheet(model: model) { showsProposal = false } }
        .sheet(isPresented: $showsStatistics) { CampShiftStatisticsSheet(model: model) { showsStatistics = false } }
        .sheet(isPresented: $showsDutyForm) { CampDutyForm(model: model) { showsDutyForm = false } }
    }

    @ViewBuilder private var content: some View {
        if model.isEmpty {
            StateView(symbol: "calendar.badge.clock", title: "Schichtplan ist leer", message: "Lege Dienste an und teile Personen ein.",
                      primary: model.rights.editsShifts && !model.sections.isEmpty ? .init(title: "Dienst anlegen", symbol: "plus") { showsDutyForm = true } : nil)
                .frame(minHeight: 320)
        } else {
            dayChips
            if model.rights.editsShifts {
                Button { showsProposal = true; Task { await model.suggest() } } label: { Label("Leere Dienste füllen", systemImage: "shuffle") }
                    .buttonStyle(CeviPrimaryButtonStyle(expands: false))
            } else if !model.rights.readOnly {
                CampRoleHint(title: "Deine Dienste sind markiert.", message: "Tauschen kannst du über «Diensttausch».")
            }
            if let day = model.selectedDay {
                VStack(spacing: 0) {
                    let rows = model.rows(for: day)
                    ForEach(rows) { row in
                        dutyRow(row, day: day)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
                .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
            }
        }
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                ForEach(model.days) { day in
                    let isOn = day.id == model.selectedDay?.id
                    Button { model.selectedDayId = day.id } label: {
                        HStack(spacing: Spacing.s1) {
                            if isOn { Image(systemName: "checkmark").accessibilityHidden(true) }
                            Text(CampRosterText.dayChip(day.date))
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, Spacing.s4)
                        .frame(minHeight: Size.touchTarget)
                        .foregroundStyle(isOn ? Color.ceviOnPrimary : Color.ceviOnSurface)
                        .background(isOn ? Color.ceviPrimary : Color.clear, in: .capsule)
                        .overlay(Capsule().stroke(Color.ceviOutline, lineWidth: isOn ? 0 : Size.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(CampRosterText.weekday(day.date) + ", " + CampCommsText.day(day.date)))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func dutyRow(_ row: CampShiftsModel.DutyRow, day: CampDay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.duty.name).font(.headline).foregroundStyle(Color.ceviOnSurface)
                    if !row.when.isEmpty { Text(row.when).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                }
                Spacer(minLength: Spacing.s2)
                if row.isStaffed {
                    CampCountChip(text: row.countText, symbol: "checkmark", tone: .good)
                } else {
                    CampCountChip(text: row.countText, symbol: "exclamationmark.triangle", tone: .warning)
                }
            }
            FlowLayout(spacing: Spacing.s2) {
                ForEach(row.shifts) { shift in
                    HStack(spacing: Spacing.s1) {
                        CampInitialsBadge(name: shift.name)
                        Text(model.label(shift)).font(.subheadline.bold()).foregroundStyle(Color.ceviOnSurface)
                    }
                    .padding(.trailing, Spacing.s3)
                    .frame(minHeight: Size.touchTarget)
                    .background(Color.ceviSecondaryContainer, in: .capsule)
                    .contextMenu {
                        if model.rights.editsShifts {
                            Button("Entfernen", systemImage: "minus.circle", role: .destructive) { Task { await model.remove(shift, from: row, day: day) } }
                        }
                    }
                }
                if model.rights.editsShifts {
                    Button { picking = row; Task { await model.loadChoices(for: row) } } label: { Label("Person wählen", systemImage: "plus") }
                        .buttonStyle(.ceviText)
                }
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The screen reader reads one whole sentence per duty and gets the actions as rotor actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.sentence))
        .accessibilityActions {
            if model.rights.editsShifts {
                Button("Person wählen") { picking = row; Task { await model.loadChoices(for: row) } }
                ForEach(row.shifts) { shift in
                    Button("\(shift.name) entfernen") { Task { await model.remove(shift, from: row, day: day) } }
                }
            }
        }
    }
}

/// «Leere Dienste füllen»: the suggestion in lines; «Übernehmen» writes it.
struct CampShiftProposalSheet: View {
    @Bindable var model: CampShiftsModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if let error = model.error { ErrorRow(text: error) }
                    Text("Vorschlag").font(.title(.title2)).accessibilityAddTraits(.isHeader)
                    Toggle("Nur Anwesende", isOn: $model.options.onlyPresent).onChange(of: model.options.onlyPresent) { Task { await model.suggest() } }
                        .frame(minHeight: Size.touchTarget)
                    Toggle("Auch Teilnehmende", isOn: $model.options.withParticipants).onChange(of: model.options.withParticipants) { Task { await model.suggest() } }
                        .frame(minHeight: Size.touchTarget)
                    if model.isSuggesting {
                        ProgressView("Vorschlag wird berechnet").frame(maxWidth: .infinity)
                    } else if let proposal = model.proposal {
                        if proposal.shifts.isEmpty { Text("Es gibt nichts zu füllen.").foregroundStyle(Color.ceviOnSurfaceVariant) }
                        ForEach(model.proposalLines, id: \.self) { Text($0).frame(maxWidth: .infinity, alignment: .leading) }
                        if model.proposalMissing > 0 {
                            Label(model.proposalMissing == 1 ? "1 Platz bleibt offen." : "\(model.proposalMissing) Plätze bleiben offen.", systemImage: "exclamationmark.triangle")
                                .font(.subheadline).foregroundStyle(Color.ceviOnWarningContainer)
                        }
                        if proposal.truncated { Text("Der Vorschlag ist gekürzt. Fülle danach nochmals.").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                    }
                    Button("Neu mischen", systemImage: "shuffle") { Task { await model.suggest() } }.buttonStyle(.ceviText)
                    Button("Übernehmen") { Task { if await model.confirmProposal() { close() } } }
                        .buttonStyle(.ceviPrimary).disabled(model.proposal?.shifts.isEmpty ?? true || model.isSuggesting)
                }
                .padding(Spacing.s4)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .ceviScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) } }
        }
    }
}

/// «Verteilung»: how many shifts each person has, nights apart.
struct CampShiftStatisticsSheet: View {
    let model: CampShiftsModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List(Array(model.statistics.enumerated()), id: \.offset) { _, stats in
                HStack {
                    Text(CampRosterText.trimmed(stats.name) ?? CampRosterText.unknownPerson)
                    Spacer(minLength: Spacing.s2)
                    Text(stats.nightShifts > 0 ? "\(stats.count) Dienste, davon \(stats.nightShifts) Nachtwachen" : "\(stats.count) Dienste")
                        .font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                .frame(minHeight: Size.touchTarget)
                .accessibilityElement(children: .combine)
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Verteilung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig", action: close) } }
        }
    }
}

/// «Dienst anlegen»: name, day section, people per day and night watch.
struct CampDutyForm: View {
    let model: CampShiftsModel
    let close: () -> Void
    @State private var name = ""
    @State private var sectionId: UUID?
    @State private var minStaff = 2
    @State private var night = false

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.error { ErrorRow(text: error).listRowBackground(Color.clear) }
                TextField("Name", text: $name)
                Picker("Tagesabschnitt", selection: $sectionId) { ForEach(model.sections) { Text($0.name).tag(Optional($0.id)) } }
                Stepper(value: $minStaff, in: 1...20) { Text("Personen pro Tag: \(minStaff)") }
                Toggle("Nachtwache", isOn: $night)
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Dienst anlegen")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { sectionId = sectionId ?? model.sections.first?.id }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anlegen") {
                        guard let sectionId else { return }
                        Task { if await model.createDuty(name: name, sectionId: sectionId, minStaff: minStaff, night: night) { close() } }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("T2 Normal") { CampRosterPreview.shifts() }
#Preview("T2 Nacht") { CampRosterPreview.shifts().preferredColorScheme(.dark) }
#Preview("T2 Laden") { CampRosterPreview.shifts(phase: .loading) }
#Preview("T2 Leer") { CampRosterPreview.shifts(empty: true) }
#Preview("T2 Fehler") { CampRosterPreview.shifts(phase: .failed(state: nil, text: "x")) }
#Preview("T2 Ohne Netz") { CampRosterPreview.shifts(offline: true) }
#Preview("T2 Nur lesen (Team)") { CampRosterPreview.shifts(role: .team) }
#Preview("T2 Lager abgeschlossen") { CampRosterPreview.shifts(status: "abgeschlossen") }
#Preview("T2 Vorschlag") { CampRosterPreview.proposal() }
#Preview("T2 Textgrösse AX3") { CampRosterPreview.shifts().dynamicTypeSize(.accessibility3) }
#endif
