import SwiftUI

/// L27: the page of one camp day: day chief, «Wichtig», ideas, programme pictures, weather and the to-dos of the day.
@MainActor @Observable
final class CampDayPageModel: CampTodoModel {
    let dayId: UUID
    let date: Date
    var detail: CampDayPageDetail?

    init(active: ActiveCamp, personId: UUID, dayId: UUID, date: Date) {
        self.dayId = dayId
        self.date = date
        super.init(active: active, personId: personId)
    }

    var headline: String {
        guard let camp = active.camp else { return CampOnSiteText.dayTitle(date) }
        let day = CampTaskText.days(from: camp.from, to: date) + 1
        return String(localized: "Tag \(day), \(CampOnSiteText.dayTitle(date))")
    }

    var chiefName: String? {
        detail?.page?.chief.flatMap { CampTaskText.personName(name: $0.name, ceviName: $0.ceviName) }
    }

    var weather: String? { detail?.weather.flatMap(CampOnSiteText.weather) }
    var weatherWarnings: [String] { (detail?.weather?.warnings ?? []).compactMap(CampOnSiteText.warning) }

    private func blocks(_ kind: CampDayBlockKind) -> [CampDayBlock] { (detail?.blocks ?? []).filter { $0.kind == kind }.sorted { $0.order < $1.order } }
    var important: [CampDayBlock] { blocks(.important) }
    var ideas: [CampDayBlock] { blocks(.idea) }
    var pictures: [CampDayBlock] { blocks(.programPicture) }
    var note: String? { CampRosterText.trimmed(detail?.page?.note) }

    /// Nothing entered for this day.
    var isEmpty: Bool {
        chiefName == nil && weather == nil && note == nil && important.isEmpty && ideas.isEmpty && pictures.isEmpty && todos.isEmpty
    }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let loaded = try await client.campDayPage(campId: campId, dayId: dayId)
            detail = loaded
            todos = loaded.tasks.sorted { ($0.order, $0.title) < ($1.order, $1.title) }
            self.loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: detail != nil)
        }
    }
}

/// The list of all camp days with their chief (the way to a day page from the «Mehr» sheet).
@MainActor @Observable
final class CampDayListModel: CampRosterModel {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let chief: String?
        let hasPage: Bool
    }

    var rows: [Row] = []

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            rows = try await client.campDayPages(campId: campId).sorted { $0.date < $1.date }.map { entry in
                let chief = entry.page?.chief.flatMap { CampTaskText.personName(name: $0.name, ceviName: $0.ceviName) }
                return Row(id: entry.dayId, date: entry.date, title: CampOnSiteText.dayTitle(entry.date), chief: chief, hasPage: entry.page != nil)
            }
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !rows.isEmpty)
        }
    }
}
