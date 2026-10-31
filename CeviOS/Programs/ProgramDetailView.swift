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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let program = model.program {
                content(program)
            } else if let error = model.loadError {
                ErrorRow(text: error).padding(Spacing.s4)
            } else {
                LoadingView(label: "Lädt")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ceviScreenBackground()
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

    /// Horizontal tiles and rows, stacked at accessibility text sizes.
    private var adaptiveRow: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.s2))
    }

    private func content(_ program: Program) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                header(program)
                tiles(program)
                infoCard(program)
                contactsCard(program)
                if !program.children.isEmpty { participation(program) }
                leadershipSections(program)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: Size.contentMax)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(program.title)
                .font(.title(.title1))
                .foregroundStyle(Color.ceviOnSurface)
                .strikethrough(program.status == .cancelled)
                .accessibilityAddTraits(.isHeader)
            let subtitle = (program.units.map(\.name) + [program.firstDay.map(ProgramFormat.shortDate)].compactMap { $0 })
                .joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            ProgramStatusLabel(status: program.status).padding(.top, Spacing.s1)
            if program.status == .review {
                Text("Dieses Programm wird von der Leitung geprüft. Eine Anmeldung ist im Moment nicht möglich.")
                    .font(.callout)
                    .foregroundStyle(Color.ceviOnSurface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Treffpunkt and Schluss tiles: time in title style, place below.
    @ViewBuilder
    private func tiles(_ program: Program) -> some View {
        let startTime = program.isAllDay ? nil : program.start.map(ProgramFormat.clock)
        let endTime = program.closingTime ?? (program.isAllDay ? nil : program.end.map(ProgramFormat.clock))
        let showStart = startTime != nil || program.meetingPoint != nil
        let showEnd = endTime != nil || program.closingPlace != nil
        if showStart || showEnd {
            adaptiveRow {
                if showStart { tile("Treffpunkt", time: startTime, place: program.meetingPoint) }
                if showEnd { tile("Schluss", time: endTime, place: program.closingPlace) }
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, time: String?, place: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(title).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            if let time { Text(time).font(.title(.title2)).foregroundStyle(Color.ceviOnSurface) }
            if let place { Text(place).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func infoCard(_ program: Program) -> some View {
        let location = program.location.flatMap { $0.isEmpty ? nil : $0 }
        let description = program.description.flatMap { $0.isEmpty ? nil : $0 }
        let when = scheduleText(program)
        if location != nil || program.bring != nil || description != nil || when != nil {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if let when { infoRow("Wann", text: when, symbol: "calendar") }
                if let location { infoRow("Ort", text: location, symbol: "mappin.and.ellipse") }
                if let bring = program.bring { infoRow("Mitnehmen", text: bring, symbol: "backpack") }
                if let description { infoRow("Info", text: description, symbol: "info.circle") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ceviCard()
        }
    }

    private func infoRow(_ title: LocalizedStringKey, text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Image(systemName: symbol).foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                Text(text).font(.body).foregroundStyle(Color.ceviOnSurface)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Full dates, only where the subtitle and tiles are not enough: all-day and multi-day programs.
    private func scheduleText(_ program: Program) -> String? {
        guard let first = program.firstDay, let last = program.lastDay else { return nil }
        let style = Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)
        if program.isAllDay {
            return first == last ? String(localized: "\(first.formatted(style)), ganztägig")
                : String(localized: "\(first.formatted(style)) bis \(last.formatted(style))")
        }
        guard first != last, let start = program.start, let end = program.end else { return nil }
        let timed = Date.FormatStyle(date: .complete, time: .shortened, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)
        return String(localized: "\(start.formatted(timed)) bis \(end.formatted(timed))")
    }

    private func participation(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Kommen deine Kinder?")
                .font(.headline)
                .foregroundStyle(Color.ceviOnSurface)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Spacing.s2)
            ForEach(program.children) { child in
                adaptiveRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(child.firstName).font(.body.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
                        answerStatus(child.answer)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    if program.canAnswer {
                        AnswerButtons(name: child.firstName, selected: child.answer, disabled: model.saving.contains(child.id)) { answer in
                            Task { await model.answer(answer, for: child, programId: program.id, client: appState.client) }
                        }
                    }
                }
            }
            if let error = model.answerError { ErrorRow(text: error) }
            if !program.canAnswer {
                Text("Die Anmeldung ist nicht mehr möglich.")
                    .font(.footnote)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
    }

    /// Status in symbol and word, not color alone.
    @ViewBuilder
    private func answerStatus(_ answer: Answer?) -> some View {
        Group {
            switch answer {
            case .yes: Label("Kommt", systemImage: "checkmark.circle.fill").foregroundStyle(Color.ceviOnSuccessContainer)
            case .no: Label("Kommt nicht", systemImage: "xmark.circle.fill").foregroundStyle(Color.ceviOnErrorContainer)
            case nil: Label("Noch offen", systemImage: "circle.dashed").foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func leadershipSections(_ program: Program) -> some View {
        if let profile = appState.profile {
            let permissions = LeadershipPermissions(profile: profile)
            if permissions.canRegisterAsLeader(for: program), let own = program.ownRegistration {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    sectionTitle("Meine Anmeldung als Leitung")
                    AnswerButtons(name: String(localized: "Ich"), selected: own.answer, disabled: model.savingOwn) { answer in
                        Task { await model.setOwnRegistration(answer, programId: program.id, client: appState.client) }
                    }
                    if own == .open {
                        Text("Noch keine Antwort").font(.callout).foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                    if program.children.isEmpty, let error = model.answerError { ErrorRow(text: error) }
                }
            }
            if permissions.canSeeOverview(of: program) || permissions.canAssign {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    sectionTitle("Leitung")
                    VStack(spacing: 0) {
                        if permissions.canSeeOverview(of: program) {
                            NavigationLink { ParticipationOverviewView(programId: program.id) } label: {
                                linkRow("Anmeldungen", symbol: "person.3")
                            }
                        }
                        if permissions.canAssign {
                            NavigationLink {
                                AssignmentView(program: program, profile: profile) { Task { await model.load(programId: program.id, client: appState.client) } }
                            } label: {
                                linkRow("Stufen und Sichtbarkeit", symbol: "slider.horizontal.3")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .ceviCard(padding: 0)
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.ceviOnSurface)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Spacing.s2)
    }

    private func linkRow(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: symbol).foregroundStyle(Color.ceviAccent).accessibilityHidden(true)
            Text(title).font(.body).foregroundStyle(Color.ceviOnSurface)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .frame(minHeight: Size.touchTarget)
        .contentShape(Rectangle())
    }

    private func contactsCard(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("Kontaktperson").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            if model.contacts.isEmpty {
                Text("Stufenleitung").font(.body.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
            } else {
                ForEach(model.contacts) { contact in
                    HStack(spacing: Spacing.s3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(contact.name).font(.body.weight(.semibold)).foregroundStyle(Color.ceviOnSurface)
                            if let ceviName = contact.ceviName {
                                Text(ceviName).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        if let phone = contact.phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) {
                            Link(destination: url) { circleIcon("phone.fill") }
                                .accessibilityLabel(Text("\(contact.name) anrufen, \(phone)"))
                        }
                    }
                }
            }
            ForEach(chatUnits(program)) { unit in
                Button { Task { await openDirectChat(unit: unit) } } label: {
                    HStack(spacing: Spacing.s3) {
                        Text("Nachricht an die Stufenleitung \(unit.name)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.ceviAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        circleIcon("message.fill")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let error = directChatError { ErrorRow(text: error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ceviCard()
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(Color.ceviAccent)
            .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
            .background(Color.ceviSecondaryContainer, in: Circle())
            .accessibilityHidden(true)
    }
}
