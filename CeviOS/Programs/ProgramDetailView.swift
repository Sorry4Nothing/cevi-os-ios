import SwiftUI

@MainActor @Observable
final class ProgramDetailModel {
    private(set) var program: Program?
    private(set) var contacts: [Contact] = []
    private(set) var loadError: String?
    /// Children whose answer is being saved. Blocks double taps.
    private(set) var saving: Set<UUID> = []
    private(set) var savingOwn = false
    var answerError: String?

    func load(programId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            program = try await client.program(id: programId)
            loadError = nil
        } catch is CancellationError {
            return
        } catch let error as APIError {
            loadError = error.displayText
            return
        } catch {
            loadError = APIError.network.displayText
            return
        }
        // Contacts are not critical: without them the detail still works.
        contacts = (try? await client.contacts(programId: programId)) ?? []
    }

    func setOwnRegistration(_ answer: Answer, programId: UUID, client: APIClient?) async {
        guard let client, !savingOwn else { return }
        savingOwn = true
        answerError = nil
        defer { savingOwn = false }
        do {
            try await client.setOwnRegistration(programId: programId, answer: answer)
            await load(programId: programId, client: client)
        } catch let error as APIError {
            let message = LeadershipMessages.message(for: error)
            answerError = message.text
            if message.reload { await load(programId: programId, client: client) }
        } catch {
            answerError = APIError.network.displayText
        }
    }

    func answer(_ answer: Answer, for child: ProgramChild, programId: UUID, client: APIClient?) async {
        guard let client, !saving.contains(child.id) else { return }
        saving.insert(child.id)
        answerError = nil
        defer { saving.remove(child.id) }
        do {
            try await client.setParticipation(programId: programId, childId: child.id, answer: answer)
            await load(programId: programId, client: client)
        } catch let error as APIError {
            let message = ParticipationMessages.message(for: error)
            answerError = message.text
            if message.reload { await load(programId: programId, client: client) }
        } catch {
            answerError = APIError.network.displayText
        }
    }
}

struct ProgramDetailView: View {
    @Environment(AppState.self) private var appState
    let programId: UUID
    @State private var model = ProgramDetailModel()
    @State private var directChat: ChatSummary?
    @State private var directChatError: String?

    var body: some View {
        Group {
            if let program = model.program {
                content(program)
            } else if let error = model.loadError {
                ErrorRow(text: error).padding()
            } else {
                ProgressView().accessibilityLabel(Text("Lädt"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(programId: programId, client: appState.client) }
        .navigationDestination(item: $directChat) { chat in
            if let profile = appState.profile { ChatView(chat: chat, profile: profile) }
        }
    }

    /// Parents write to the unit leaders of the unit their child belongs to. The direct chat is created if needed.
    private func openDirectChat(unit: UnitRef) async {
        directChatError = nil
        guard let client = appState.client else { return }
        do {
            let id = try await client.openDirectChat(unitId: unit.id)
            directChat = try await client.chats().first { $0.id == id }
        } catch let error as APIError {
            directChatError = error.displayText
        } catch {
            directChatError = APIError.network.displayText
        }
    }

    /// Units of the program in which the person has a child.
    private func chatUnits(_ program: Program) -> [UnitRef] {
        guard let profile = appState.profile else { return [] }
        let childUnits = Set(profile.children.map(\.unitId))
        return program.units.filter { childUnits.contains($0.id) }
    }

    private func content(_ program: Program) -> some View {
        List {
            Section {
                Text(program.title).font(.title2.bold()).strikethrough(program.status == .cancelled)
                ProgramStatusLabel(status: program.status)
                if program.status == .review {
                    Text("Dieses Programm wird von der Leitung geprüft. Eine Anmeldung ist im Moment nicht möglich.")
                        .font(.callout)
                }
                scheduleRows(program)
                if let location = program.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if !program.units.isEmpty {
                    Label(program.units.map(\.name).joined(separator: ", "), systemImage: "person.3")
                }
            }
            details(program)
            if !program.children.isEmpty { participation(program) }
            leadershipSections(program)
            contactsSection(program)
            if let description = program.description, !description.isEmpty {
                Section("Beschreibung") { Text(description) }
            }
        }
    }

    @ViewBuilder
    private func scheduleRows(_ program: Program) -> some View {
        if program.isAllDay, let first = program.firstDay, let last = program.lastDay {
            let style = Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)
            if first == last {
                Label("\(first.formatted(style)), ganztägig", systemImage: "calendar")
            } else {
                Label("\(first.formatted(style)) bis \(last.formatted(style))", systemImage: "calendar")
            }
        } else if let start = program.start, let end = program.end {
            let style = Date.FormatStyle(date: .complete, time: .shortened, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)
            Label("\(start.formatted(style)) bis \(end.formatted(style))", systemImage: "calendar")
        }
    }

    @ViewBuilder
    private func details(_ program: Program) -> some View {
        let hasClosing = program.closingPlace != nil || program.closingTime != nil
        if program.meetingPoint != nil || hasClosing || program.bring != nil {
            Section {
                if let meetingPoint = program.meetingPoint {
                    LabeledContent("Treffpunkt") { Text(meetingPoint) }
                }
                if hasClosing {
                    LabeledContent("Schluss") {
                        Text([program.closingTime, program.closingPlace].compactMap { $0 }.joined(separator: ", "))
                    }
                }
                if let bring = program.bring {
                    LabeledContent("Mitnehmen") { Text(bring) }
                }
            }
        }
    }

    private func participation(_ program: Program) -> some View {
        Section {
            ForEach(program.children) { child in
                VStack(alignment: .leading, spacing: 8) {
                    AnswerLabel(name: child.firstName, answer: child.answer).font(.headline)
                    if program.canAnswer {
                        AnswerButtons(name: child.firstName, selected: child.answer, disabled: model.saving.contains(child.id)) { answer in
                            Task { await model.answer(answer, for: child, programId: program.id, client: appState.client) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let error = model.answerError { ErrorRow(text: error) }
        } header: {
            Text("Anmeldung")
        } footer: {
            if !program.canAnswer {
                Text("Die Anmeldung ist nicht mehr möglich.")
            }
        }
    }

    @ViewBuilder
    private func leadershipSections(_ program: Program) -> some View {
        if let profile = appState.profile {
            let permissions = LeadershipPermissions(profile: profile)
            if permissions.canRegisterAsLeader(for: program), let own = program.ownRegistration {
                Section("Meine Anmeldung als Leitung") {
                    AnswerButtons(name: String(localized: "Ich"), selected: own.answer, disabled: model.savingOwn) { answer in
                        Task { await model.setOwnRegistration(answer, programId: program.id, client: appState.client) }
                    }
                    if own == .open { Text("Noch keine Antwort").font(.callout) }
                }
            }
            if permissions.canSeeOverview(of: program) || permissions.canAssign {
                Section("Leitung") {
                    if permissions.canSeeOverview(of: program) {
                        NavigationLink("Teilnahmen") { ParticipationOverviewView(programId: program.id) }.frame(minHeight: 44)
                    }
                    if permissions.canAssign {
                        NavigationLink("Stufen und Sichtbarkeit") {
                            AssignmentView(program: program, profile: profile) { Task { await model.load(programId: program.id, client: appState.client) } }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contactsSection(_ program: Program) -> some View {
        Section("Kontakt") {
            if model.contacts.isEmpty {
                Text("Stufenleitung")
            } else {
                ForEach(model.contacts) { contact in
                    VStack(alignment: .leading) {
                        Text(contact.ceviName.map { "\(contact.name) (\($0))" } ?? contact.name)
                        if let phone = contact.phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                            Link(phone, destination: url).frame(minHeight: 44)
                        }
                    }
                }
            }
            ForEach(chatUnits(program)) { unit in
                Button("Nachricht an die Stufenleitung \(unit.name)") { Task { await openDirectChat(unit: unit) } }
                    .frame(minHeight: 44)
            }
            if let error = directChatError { ErrorRow(text: error) }
        }
    }
}
