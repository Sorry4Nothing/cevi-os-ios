import SwiftUI

/// Programs of the next months, grouped by Swiss calendar day. Kept in memory only.
@MainActor @Observable
final class ProgramListModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// How far ahead the list reaches.
    nonisolated static let windowDays = 120

    private(set) var state: LoadState = .loading
    private(set) var sections: [DaySection] = []

    struct DaySection: Identifiable, Equatable {
        let day: Date
        let programs: [Program]
        var id: Date { day }
    }

    func load(client: APIClient?, today: Date = .now) async {
        guard let client else { return }
        let calendar = DateFormats.calendar
        let from = calendar.startOfDay(for: today)
        guard let to = calendar.date(byAdding: .day, value: Self.windowDays, to: from) else { return }
        if sections.isEmpty { state = .loading }
        do {
            let programs = try await client.programs(from: from, to: to)
            sections = Self.sections(for: programs, from: from, to: to)
            state = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            state = .failed(error.displayText)
        } catch {
            state = .failed(APIError.network.displayText)
        }
    }

    /// A multi-day program appears on every day inside the window, in the order the server sent.
    nonisolated static func sections(for programs: [Program], from: Date, to: Date) -> [DaySection] {
        var byDay: [Date: [Program]] = [:]
        for program in programs {
            for day in program.days where day >= from && day <= to {
                byDay[day, default: []].append(program)
            }
        }
        return byDay.keys.sorted().map { DaySection(day: $0, programs: byDay[$0] ?? []) }
    }
}

struct ProgramListView: View {
    @Environment(AppState.self) private var appState
    @State private var model = ProgramListModel()
    @Binding var path: [UUID]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.state {
                case .loading:
                    LoadingView(label: "Programme werden geladen")
                case .failed(let text) where model.sections.isEmpty:
                    StateView(symbol: "exclamationmark.triangle", title: "Etwas ist schiefgelaufen", message: "\(text)", tone: .error,
                              primary: .init(title: "Nochmals versuchen", symbol: "arrow.clockwise") {
                                  Task { await model.load(client: appState.client) }
                              })
                default:
                    list
                }
            }
            .navigationTitle("Programme")
            .navigationDestination(for: UUID.self) { id in ProgramDetailView(programId: id) }
        }
        .task { await model.load(client: appState.client) }
    }

    @ViewBuilder
    private var list: some View {
        if model.sections.isEmpty {
            StateView.empty(title: "Keine Programme", message: "In den nächsten Monaten ist nichts geplant.") {
                Task { await model.load(client: appState.client) }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s5) {
                    if case .failed(let text) = model.state {
                        ErrorRow(text: text)
                    }
                    ForEach(model.sections) { section in
                        DaySectionView(section: section)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
                .frame(maxWidth: Size.contentMax)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load(client: appState.client) }
            .ceviScreenBackground()
        }
    }
}

/// One day of the timeline: weekday and day number on the left, the program cards on the right.
/// At accessibility text sizes the day moves above the cards.
struct DaySectionView: View {
    let section: ProgramListModel.DaySection
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) { weekday; dayNumber }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(ProgramFormat.fullDate(section.day)))
                    .accessibilityAddTraits(.isHeader)
                cards
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.s3) {
                VStack(spacing: 0) {
                    weekday
                    dayNumber
                    Capsule()
                        .fill(Color.ceviOutlineVariant)
                        .frame(width: Size.focusBorder)
                        .padding(.vertical, Spacing.s1)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(ProgramFormat.fullDate(section.day)))
                .accessibilityAddTraits(.isHeader)
                cards
            }
        }
    }

    private var weekday: some View {
        Text(ProgramFormat.weekday(section.day))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.ceviAccent)
    }

    private var dayNumber: some View {
        Text(section.day, format: .dateTime.day().locale(Locale(identifier: "de_CH")))
            .font(.title(.day))
            .foregroundStyle(Color.ceviOnSurface)
    }

    private var cards: some View {
        VStack(spacing: Spacing.s2) {
            ForEach(section.programs) { program in
                NavigationLink(value: program.id) { ProgramRow(program: program, day: section.day) }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProgramRow: View {
    let program: Program
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(([ProgramFormat.time(of: program, on: day)] + program.units.map(\.name)).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ceviAccent)
            Text(program.title)
                .font(.title(.cardTitle))
                .foregroundStyle(Color.ceviOnSurface)
                .strikethrough(program.status == .cancelled)
            if let location = program.location, !location.isEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            ProgramStatusLabel(status: program.status)
            ForEach(program.children) { child in
                AnswerLabel(name: child.firstName, answer: child.answer)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget, alignment: .leading)
        .ceviCard()
        .contentShape(Radius.shape(Radius.md))
        .accessibilityElement(children: .combine)
    }
}

/// Status chip: symbol and word in a capsule, never only color. Nothing for a normal active program.
struct ProgramStatusLabel: View {
    let status: ProgramStatus

    var body: some View {
        switch status {
        case .active:
            EmptyView()
        case .cancelled:
            chip("Abgesagt", symbol: "xmark.octagon.fill", foreground: .ceviOnErrorContainer, background: .ceviErrorContainer)
        case .review:
            chip("Wird geprüft", symbol: "questionmark.circle.fill", foreground: .ceviOnWarningContainer, background: .ceviWarningContainer)
        }
    }

    private func chip(_ title: LocalizedStringKey, symbol: String, foreground: Color, background: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
    }
}

/// "Noah kommt" with a symbol, so the state is readable without color.
struct AnswerLabel: View {
    let name: String
    let answer: Answer?

    var body: some View {
        switch answer {
        case .yes:
            Label("\(name) kommt", systemImage: "checkmark.circle.fill").foregroundStyle(Color.ceviOnSuccessContainer)
        case .no:
            Label("\(name) kommt nicht", systemImage: "xmark.circle.fill").foregroundStyle(Color.ceviOnErrorContainer)
        case nil:
            Label("Zusage für \(name) offen", systemImage: "circle.dashed").foregroundStyle(Color.ceviOnSurfaceVariant)
        }
    }
}

nonisolated enum ProgramFormat {
    /// "Ganztägig", "14:00–17:00" or, for multi-day programs, with start and end on the right days.
    static func time(of program: Program, on day: Date) -> String {
        if program.isAllDay { return String(localized: "Ganztägig") }
        guard let start = program.start, let end = program.end else { return "" }
        let calendar = DateFormats.calendar
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone)
        let startsToday = calendar.isDate(start, inSameDayAs: day)
        let endsToday = calendar.isDate(end, inSameDayAs: day)
        switch (startsToday, endsToday) {
        case (true, true): return "\(start.formatted(style))–\(end.formatted(style))"
        case (true, false): return String(localized: "ab \(start.formatted(style))")
        case (false, true): return String(localized: "bis \(end.formatted(style))")
        case (false, false): return String(localized: "Ganztägig")
        }
    }

    private static let locale = Locale(identifier: "de_CH")

    /// "SA" for the timeline.
    static func weekday(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).weekday(.abbreviated))
            .replacingOccurrences(of: ".", with: "").uppercased()
    }

    /// "Samstag, 14. November 2026" for VoiceOver.
    static func fullDate(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: DateFormats.timeZone))
    }

    /// "Sa., 14. November" for the detail subtitle.
    static func shortDate(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(locale: locale, timeZone: DateFormats.timeZone).weekday(.abbreviated).day().month(.wide))
    }

    /// "14:00" in Swiss time.
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: DateFormats.timeZone))
    }
}

#Preview("Programmkarte") {
    let day = DateFormats.calendar.startOfDay(for: .now)
    let program = Program(id: UUID(), title: "Waldweihnacht vorbereiten", status: .active, visibility: .parents, isAllDay: false,
                          start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(17 * 3600), dayFrom: nil, dayTo: nil,
                          location: "Gemeindehaus", units: [UnitRef(id: UUID(), name: "Jungschar")], description: nil,
                          children: [ProgramChild(id: UUID(), firstName: "Lena", answer: nil),
                                     ProgramChild(id: UUID(), firstName: "Noah", answer: .yes)],
                          meetingPoint: nil, closingPlace: nil, closingTime: nil, bring: nil, isRegistrationOpen: nil, ownRegistration: nil)
    NavigationStack {
        ScrollView {
            DaySectionView(section: .init(day: day, programs: [program])).padding(Spacing.s4)
        }
        .ceviScreenBackground()
    }
}
