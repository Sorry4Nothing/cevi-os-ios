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

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    ProgressView().accessibilityLabel(Text("Lädt"))
                case .failed(let text) where model.sections.isEmpty:
                    VStack(spacing: 16) {
                        ErrorRow(text: text)
                        Button("Nochmals versuchen") { Task { await model.load(client: appState.client) } }
                            .frame(minHeight: 44)
                    }
                    .padding()
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
            ContentUnavailableView("Keine Programme", systemImage: "calendar", description: Text("In den nächsten Monaten ist nichts geplant."))
        } else {
            List {
                if case .failed(let text) = model.state {
                    Section { ErrorRow(text: text) }
                }
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.programs) { program in
                            NavigationLink(value: program.id) { ProgramRow(program: program, day: section.day) }
                                .frame(minHeight: 44)
                        }
                    } header: {
                        Text(section.day, format: Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "de_CH"), timeZone: DateFormats.timeZone))
                    }
                }
            }
            .refreshable { await model.load(client: appState.client) }
        }
    }
}

struct ProgramRow: View {
    let program: Program
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.title)
                .font(.headline)
                .strikethrough(program.status == .cancelled)
            ProgramStatusLabel(status: program.status)
            Text(ProgramFormat.time(of: program, on: day))
                .font(.subheadline)
            if !program.units.isEmpty {
                Text(program.units.map(\.name).joined(separator: ", "))
                    .font(.subheadline)
            }
            ForEach(program.children) { child in
                AnswerLabel(name: child.firstName, answer: child.answer)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Status badge: icon and text, never only color. Nothing for a normal active program.
struct ProgramStatusLabel: View {
    let status: ProgramStatus

    var body: some View {
        switch status {
        case .active:
            EmptyView()
        case .cancelled:
            Label("Abgesagt", systemImage: "xmark.octagon.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Color.error)
        case .review:
            Label("Wird geprüft", systemImage: "questionmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Color.warning)
        }
    }
}

/// "Mia: Ja" with an icon, so the state is readable without color.
struct AnswerLabel: View {
    let name: String
    let answer: Answer?

    var body: some View {
        switch answer {
        case .yes:
            Label("\(name): Ja", systemImage: "checkmark.circle.fill")
        case .no:
            Label("\(name): Nein", systemImage: "xmark.circle.fill")
        case nil:
            Label("\(name): Offen", systemImage: "circle.dashed")
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
}
