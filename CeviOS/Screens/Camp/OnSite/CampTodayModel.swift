import SwiftUI

/// L4: «Heute». The shift of the person, what is important today and the own to-dos of the day.
@MainActor @Observable
final class CampTodayModel: CampTodoModel {
    struct Shift: Equatable, Identifiable {
        let id: UUID
        let title: String
        /// «07:00 bis 10:00».
        let time: String?
    }

    var today: CampToday?
    var myWeek: CampMyWeek?
    var sections: [CampDaySection] = []

    var dayId: UUID? { today?.day?.id }

    /// «Tag 3 von 8, Mittwoch, 19. Juli». Without a loaded answer the date of today.
    var headline: String {
        guard let camp = active.camp else { return CampOnSiteText.dayTitle(now()) }
        return CampOnSiteText.campDay(today?.date ?? now(), from: camp.from, to: camp.to)
    }

    var shifts: [Shift] {
        (myWeek?.shifts ?? []).filter { CampTaskText.days(from: $0.shift.date, to: today?.date ?? now()) == 0 }.map { own in
            let name = own.duty?.name ?? String(localized: "Dienst")
            let time = CampOnSiteText.timeRange(sections.first { $0.id == own.shift.sectionId }?.time)
            return Shift(id: own.id, title: time.map { String(localized: "\(name), \($0)") } ?? name, time: time)
        }
    }

    /// The «Wichtig» blocks of the day page, in their order.
    var important: [CampDayBlock] { (today?.page?.blocks ?? []).filter { $0.kind == .important }.sorted { $0.order < $1.order } }

    /// Nothing for the person today: no shift, nothing important, no to-do.
    var isEmpty: Bool { shifts.isEmpty && important.isEmpty && todos.isEmpty }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let loadedToday = try await client.campToday(campId: campId)
            // «Meine Woche» and the times of the day sections only add to the page: a failure there does not fail it.
            if let week = try? await client.campMyWeek(campId: campId) { myWeek = week }
            if sections.isEmpty, let schedule = try? await client.campSchedule(campId: campId) { sections = schedule.sections }
            today = loadedToday
            todos = (loadedToday.page?.tasks ?? []).filter { $0.responsibleId == personId }.sorted { ($0.order, $0.title) < ($1.order, $1.title) }
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: today != nil)
        }
    }
}
