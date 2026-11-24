import SwiftUI

/// «Mein Kalender» of the next months, grouped by Swiss calendar day. Kept in memory only.
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
            let programs = try await Self.allPrograms(client: client, from: from, to: to)
            sections = Self.sections(for: programs, from: from, to: to)
            state = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            state = .failed(error.displayText)
        } catch {
            state = .failed(APIError.network.displayText)
        }
    }

    /// Follows the pages of `GET /termine/mein` (an event once, even if the page border repeats it).
    nonisolated static func allPrograms(client: APIClient, from: Date, to: Date) async throws -> [Program] {
        var page = try await client.calendarEvents(from: from, to: to)
        // Guard against a server that never ends: 400 days hold far fewer pages.
        for _ in 0..<20 where page.hasMore {
            guard let next = page.next else { break }
            page = page.appending(try await client.calendarEvents(from: from, to: to, after: next))
        }
        return page.events.map(Program.init(event:))
    }

    /// «Gruppen deiner Kinder: …» for parents, «Deine Gruppen: …» for leaders; `nil` without units.
    nonisolated static func subtitle(for profile: Profile?) -> String? {
        guard let profile else { return nil }
        let isParent = !profile.children.isEmpty
        let unitIds = isParent ? Set(profile.children.map(\.unitId)) : Set(profile.units.map(\.id))
        let names = profile.units.filter { unitIds.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return nil }
        let list = names.joined(separator: ", ")
        return isParent ? String(localized: "Gruppen deiner Kinder: \(list)") : String(localized: "Deine Gruppen: \(list)")
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
