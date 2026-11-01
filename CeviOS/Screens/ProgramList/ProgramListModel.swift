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
    nonisolated static let windowMonths = 6

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
        guard let to = calendar.date(byAdding: .month, value: Self.windowMonths, to: from) else { return }
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
