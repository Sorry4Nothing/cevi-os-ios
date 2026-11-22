import SwiftUI

/// L29: the own copy of the packing list: template points with the own state, and the own points.
@MainActor @Observable
final class CampPackingModel: CampRosterModel {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let text: String
        var checked: Bool
        let leadershipOnly: Bool
        /// A point the person added: only they see it.
        let isOwn: Bool
    }

    struct Section: Equatable, Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    var list: CampPackingList?

    var ticks: Bool { onSite.ticksPacking }
    /// The camp leadership writes the template; everybody else adds own points.
    var addsToTemplate: Bool { onSite.editsPackingTemplate }
    var canAdd: Bool { ticks }

    private var rows: [(section: String, order: Int, row: Row)] {
        guard let list else { return [] }
        let template = list.points.filter { $0.state != .removed }.map { ($0.section, $0.order, Row(id: $0.id, text: $0.text, checked: $0.state == .checked, leadershipOnly: $0.leadershipOnly, isOwn: false)) }
        let own = list.own.map { ($0.section, $0.order, Row(id: $0.id, text: $0.text, checked: $0.checked, leadershipOnly: false, isOwn: true)) }
        return template + own
    }

    var sections: [Section] {
        var titles: [String] = []
        for entry in rows.sorted(by: { ($0.order, $0.row.text) < ($1.order, $1.row.text) }) where !titles.contains(entry.section) { titles.append(entry.section) }
        return titles.map { title in
            Section(title: title, rows: rows.filter { $0.section == title }.sorted { ($0.order, $0.row.isOwn ? 1 : 0, $0.row.text) < ($1.order, $1.row.isOwn ? 1 : 0, $1.row.text) }.map(\.row))
        }
    }

    var total: Int { rows.count }
    var packed: Int { rows.count { $0.row.checked } }
    var progress: String { String(localized: "\(packed) von \(total) eingepackt") }
    var sectionNames: [String] { sections.map(\.title) }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            list = try await client.campPackingList(campId: campId)
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: list != nil)
        }
    }

    /// Ticks at once and tells the server; a failure puts the tick back. The same call repeats the same result.
    func toggle(_ row: Row) async {
        guard ticks, list != nil else { return }
        let checked = !row.checked
        set(row, checked: checked)
        let result: Bool? = await write { client, campId in
            if row.isOwn {
                return try await client.updateOwnCampPackingPoint(campId: campId, pointId: row.id, CampOwnPackingPointPatch(checked: checked)).checked
            }
            return try await client.setCampPackingState(campId: campId, pointId: row.id, checked ? .checked : .open) == .checked
        }
        if result == nil { set(row, checked: !checked) }
    }

    private func set(_ row: Row, checked: Bool) {
        guard let current = list else { return }
        if row.isOwn {
            list = CampPackingList(points: current.points, own: current.own.map { $0.id == row.id ? CampOwnPackingPoint(id: $0.id, section: $0.section, text: $0.text, checked: checked, order: $0.order) : $0 })
        } else {
            list = CampPackingList(points: current.points.map {
                $0.id == row.id ? CampPackingPoint(id: $0.id, version: $0.version, section: $0.section, text: $0.text, leadershipOnly: $0.leadershipOnly, order: $0.order, state: checked ? .checked : .open) : $0
            }, own: current.own)
        }
    }

    /// «Punkt hinzufügen». `true` when it was written; the sheet then closes.
    func add(section: String, text: String, leadershipOnly: Bool) async -> Bool {
        guard canAdd else { return false }
        let title = section.trimmingCharacters(in: .whitespaces), body = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !body.isEmpty else {
            error = String(localized: "Gib einen Abschnitt und einen Punkt ein.")
            return false
        }
        let written: Bool
        if addsToTemplate {
            written = await write { try await $0.createCampPackingPoint(campId: $1, CampPackingPointCreate(section: title, text: body, leadershipOnly: leadershipOnly ? true : nil)) } != nil
        } else {
            written = await write { try await $0.createOwnCampPackingPoint(campId: $1, CampOwnPackingPointCreate(section: title, text: body)) } != nil
        }
        guard written else { return false }
        await load()
        show(Notice(title: String(localized: "Punkt hinzugefügt."), message: nil))
        return true
    }
}
