import SwiftUI

/// What the role may do in the roster screens (rooms, trips, groups, shifts, swaps, counting). The defaults of the
/// rights matrix (`docs/lager.md`): the app shows only these actions, the server decides again. A missing action is a missing button.
nonisolated struct CampRosterRights: Equatable, Sendable {
    let role: CampRole?
    /// The camp is completed or archived.
    let readOnly: Bool

    private var isLead: Bool { role == .campLeader }
    private var isLeadership: Bool { role == .campLeader || role == .leader }

    /// Rooms, trips and groups: the camp leadership places the people.
    var placesPeople: Bool { !readOnly && isLead }
    var editsShifts: Bool { !readOnly && isLeadership }
    var decidesSwaps: Bool { !readOnly && isLead }
    var requestsSwaps: Bool { !readOnly && (isLeadership || role == .team) }
    var ticks: Bool { !readOnly && (isLeadership || role == .team) }
    var resets: Bool { !readOnly && isLeadership }
    /// Leads read all swaps, the others their own.
    var seesAllSwaps: Bool { isLead }
    /// The camp is open but the role changes nothing here: the screen says so («Nur lesen.»).
    var isLockedByRole: Bool { !readOnly && !isLead }
}

/// A person the screen can place somewhere: a team member (`personId`) or a participant (`participantId`).
/// The name is what the server sent; without a name the label is neutral (backend gap B1 in `docs/lager.md`).
nonisolated struct CampPersonChoice: Equatable, Identifiable, Sendable {
    let id: UUID
    let isParticipant: Bool
    let label: String
    var detail: String?
}

nonisolated enum CampRosterText {
    /// Shown where the data layer gives only an id (no member list for non-admins).
    static var unknownPerson: String { String(localized: "Person") }

    static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// «Mara (Luchs)»; without a name «Person».
    static func label(name: String?, ceviName: String?) -> String {
        guard let name = trimmed(name) else { return trimmed(ceviName) ?? unknownPerson }
        guard let cevi = trimmed(ceviName) else { return name }
        return "\(name) (\(cevi))"
    }

    static func fullName(first: String?, last: String?) -> String? {
        trimmed([first, last].compactMap(trimmed).joined(separator: " "))
    }

    /// «MA» for «Mara», «JB» for «Jonas Brun».
    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        if words.count > 1 { return words.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    /// «5 von 6».
    static func occupancy(_ occupied: Int, of places: Int) -> String { String(localized: "\(occupied) von \(places)") }

    /// «5 von 6 Plätzen belegt» for the screen reader (numbers as words are read by VoiceOver itself).
    static func occupancySpoken(_ occupied: Int, of places: Int) -> String {
        places == 1 ? String(localized: "\(occupied) von 1 Platz belegt") : String(localized: "\(occupied) von \(places) Plätzen belegt")
    }

    static func children(_ count: Int) -> String { count == 1 ? String(localized: "1 Kind") : String(localized: "\(count) Kinder") }
    static func people(_ count: Int) -> String { count == 1 ? String(localized: "1 Person") : String(localized: "\(count) Personen") }

    /// «Mara, Lea, Jonas und 2 weitere».
    static func summary(_ names: [String], shown: Int = 3) -> String {
        guard names.count > shown else {
            guard names.count > 1, let last = names.last else { return names.first ?? "" }
            return names.dropLast().joined(separator: ", ") + String(localized: " und ") + last
        }
        let rest = names.count - shown
        let more = rest == 1 ? String(localized: "1 weitere") : String(localized: "\(rest) weitere")
        return names.prefix(shown).joined(separator: ", ") + String(localized: " und ") + more
    }

    private static func style() -> Date.FormatStyle { Date.FormatStyle(locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone) }

    static func weekday(_ date: Date) -> String { date.formatted(style().weekday(.wide)) }

    /// «Mo 17.».
    static func dayChip(_ date: Date) -> String {
        let weekday = date.formatted(style().weekday(.abbreviated)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return "\(weekday) \(date.formatted(style().day()))."
    }

    /// «gestern 21:10», older days with the date.
    static func stamp(_ date: Date, now: Date) -> String {
        let time = date.formatted(style().hour().minute())
        switch CampTaskText.days(from: date, to: now) {
        case 0: return String(localized: "heute \(time)")
        case 1: return String(localized: "gestern \(time)")
        default: return "\(CampCommsText.day(date)), \(time)"
        }
    }
}

/// Shared state of the roster screens: loading, message line, notice, and the people a sheet offers.
@MainActor @Observable
class CampRosterModel {
    struct Notice: Equatable {
        let title: String
        var message: String?
    }

    let active: ActiveCamp
    @ObservationIgnored var now: () -> Date = { Date() }
    var phase: CampPhase = .loading
    var staleSince: Date?
    var error: String?
    var notice: Notice?
    /// The people of the open picker.
    var choices: [CampPersonChoice] = []
    var choicesLoading = false
    var choicesError: String?

    init(active: ActiveCamp) { self.active = active }

    var rights: CampRosterRights { CampRosterRights(role: active.role, readOnly: active.isReadOnly) }

    /// Overridden by every screen.
    func load() async {}

    func loaded() {
        phase = .loaded
        staleSince = nil
        error = nil
    }

    /// A failed read: without content the whole screen shows it, with content only the message line (and the stand note offline).
    func failLoad(_ error: any Error, hasContent: Bool) {
        let failure = CampPhase(error: error)
        guard hasContent else { phase = failure; return }
        self.error = failure.failureText
        if case .failed(.offline?, _) = failure { staleSince = staleSince ?? now() }
    }

    func show(_ notice: Notice) {
        self.notice = notice
        AccessibilityNotification.Announcement([notice.title, notice.message].compactMap { $0 }.joined(separator: " ")).post()
    }

    func dismissNotice() { notice = nil }

    func noticeData(undo: (() -> Void)? = nil) -> CampNoticeData? {
        notice.map { CampNoticeData(title: $0.title, message: $0.message, undo: undo, dismiss: dismissNotice) }
    }

    /// Runs a write. Every failure becomes the message line («Deine Eingabe ist noch da.»); `nil` then.
    func write<Value: Sendable>(_ perform: @escaping (APIClient, UUID) async throws -> Value) async -> Value? {
        guard let client = active.client, let campId = active.camp?.id else { return nil }
        switch await CampCommsWrite.run({ try await perform(client, campId) }) {
        case .done(let value):
            error = nil
            return value
        case .invalid(let text), .failed(let text):
            error = text
            return nil
        }
    }

    /// A write with a row version: on 409 `VERSION_KONFLIKT` somebody changed the row, the list is loaded anew.
    func writeVersioned<Value: Sendable, Row: Decodable & Sendable>(as row: Row.Type, _ perform: @escaping (APIClient, UUID) async throws -> Value) async -> Value? {
        guard let client = active.client, let campId = active.camp?.id else { return nil }
        switch await CampCommsWrite.run(as: row, { try await perform(client, campId) }) {
        case .done(let value):
            error = nil
            return value
        case .conflict:
            error = String(localized: "Jemand hat das gerade geändert. Die Liste wird neu geladen.")
            await load()
            return nil
        case .invalid(let text), .failed(let text):
            error = text
            return nil
        }
    }

    /// Fills `choices` for a picker.
    func loadChoices(_ fetch: @escaping (APIClient, UUID) async throws -> [CampPersonChoice]) async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        choicesLoading = true
        choicesError = nil
        defer { choicesLoading = false }
        do {
            choices = try await fetch(client, campId)
        } catch is CancellationError {
        } catch {
            choices = []
            choicesError = CampPhase(error: error).failureText
        }
    }
}

// MARK: Views shared by the roster screens

/// Two initials in a circle. Decorative: the names stand next to it.
struct CampInitialsBadge: View {
    let name: String

    var body: some View {
        Text(CampRosterText.initials(name))
            .font(.caption2.bold())
            .foregroundStyle(Color.ceviOnPrimary)
            .frame(width: 30, height: 30)
            .background(Color.ceviPrimary, in: Circle())
            .overlay(Circle().stroke(Color.ceviSurfaceContainerLow, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// Overlapping initials and the names as one line («Mara, Lea, Jonas und 2 weitere»).
struct CampPeopleLine: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            HStack(spacing: Spacing.s2) {
                HStack(spacing: -8) { ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { CampInitialsBadge(name: $0.element) } }
                Text(CampRosterText.summary(names)).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CampRosterText.summary(names, shown: names.count)))
        }
    }
}

/// «5 von 6», «Voll», «Überbelegt»: a word with a symbol, never color alone.
struct CampCountChip: View {
    enum Tone { case neutral, good, warning }

    let text: String
    var symbol: String?
    var tone: Tone = .neutral

    var body: some View {
        Group {
            if let symbol { Label(text, systemImage: symbol) } else { Text(text) }
        }
        .font(.caption.bold())
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.s2).padding(.vertical, Spacing.s1)
        .background(background, in: .capsule)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Color.ceviOnSecondaryContainer
        case .good: Color.ceviOnSuccessContainer
        case .warning: Color.ceviOnWarningContainer
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Color.ceviSecondaryContainer
        case .good: Color.ceviSuccessContainer
        case .warning: Color.ceviWarningContainer
        }
    }
}

/// «Nur lesen. Die Einteilung macht die Lagerleitung.»
struct CampRoleHint: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Label(title, systemImage: "eye").font(.headline)
            Text(message).font(.subheadline)
        }
        .foregroundStyle(Color.ceviOnSecondaryContainer)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.ceviSecondaryContainer, in: Radius.shape(Radius.md))
        .accessibilityElement(children: .combine)
    }
}

/// «Person suchen», choose one or several, «Zuweisen». Used for rooms, trips and shifts.
struct CampPersonPicker<Header: View>: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let model: CampRosterModel
    @ViewBuilder var header: Header
    let confirm: ([CampPersonChoice]) -> Void
    let close: () -> Void
    @State private var search = ""
    @State private var selected: Set<UUID> = []

    private var shown: [CampPersonChoice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? model.choices : model.choices.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                header
                if let error = model.choicesError { ErrorRow(text: error).listRowBackground(Color.clear) }
                if model.choicesLoading {
                    ProgressView("Personen werden geladen").frame(maxWidth: .infinity)
                } else if model.choices.isEmpty && model.choicesError == nil {
                    Text("Es gibt niemanden mehr, der noch fehlt.").foregroundStyle(Color.ceviOnSurfaceVariant)
                }
                ForEach(shown) { choice in
                    Button { if !selected.insert(choice.id).inserted { selected.remove(choice.id) } } label: {
                        HStack(spacing: Spacing.s3) {
                            Image(systemName: selected.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(choice.id) ? Color.ceviAccent : Color.ceviOnSurfaceVariant)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(choice.label).foregroundStyle(Color.ceviOnSurface)
                                if let detail = choice.detail { Text(detail).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant) }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: Size.touchTarget)
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(selected.contains(choice.id) ? .isSelected : [])
                }
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .searchable(text: $search, prompt: "Person suchen")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen", action: close) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(confirmTitle) { confirm(model.choices.filter { selected.contains($0.id) }) }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }
}

extension CampPersonPicker where Header == EmptyView {
    init(title: LocalizedStringKey, confirmTitle: LocalizedStringKey, model: CampRosterModel,
         confirm: @escaping ([CampPersonChoice]) -> Void, close: @escaping () -> Void) {
        self.init(title: title, confirmTitle: confirmTitle, model: model, header: { EmptyView() }, confirm: confirm, close: close)
    }
}
