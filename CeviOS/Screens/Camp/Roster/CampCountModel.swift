import SwiftUI

/// L25: the counting list. The ticks are shared: everybody sees them at once.
@MainActor @Observable
final class CampCountModel: CampRosterModel {
    enum Scope: Hashable { case all, team, group(UUID) }

    struct Row: Equatable, Identifiable {
        let id: UUID
        let participantId: UUID?
        let personId: UUID?
        let label: String
        var checked: Bool
    }

    /// The ticks before a reset, for «Rückgängig».
    struct Snapshot: Equatable {
        var participantIds: [UUID]
        var personIds: [UUID]
        var isEmpty: Bool { participantIds.isEmpty && personIds.isEmpty }
    }

    var rows: [Row] = []
    var present = 0
    var total = 0
    var groups: [CampGroup] = []
    var scope: Scope = .all
    var snapshot: Snapshot?

    private var filter: CampCountFilter {
        switch scope {
        case .all: CampCountFilter()
        case .team: CampCountFilter(kind: .team)
        case .group(let id): CampCountFilter(groupId: id)
        }
    }

    static func row(_ entry: CampCountEntry) -> Row {
        let name = entry.name ?? CampRosterText.fullName(first: entry.firstName, last: entry.lastName)
        return Row(id: entry.id, participantId: entry.participantId, personId: entry.personId,
                   label: CampRosterText.label(name: name, ceviName: entry.ceviName), checked: entry.checked)
    }

    func select(_ scope: Scope) async {
        self.scope = scope
        await load()
    }

    private func fetch(_ client: APIClient, _ campId: UUID, filter: CampCountFilter) async throws -> (entries: [CampCountEntry], present: Int, total: Int) {
        var all: [CampCountEntry] = []
        var cursor: UUID?
        var present = 0, total = 0
        repeat {
            let page = try await client.campCount(campId: campId, filter: filter, after: cursor, limit: 100)
            all += page.entries
            present = page.present
            total = page.total
            cursor = page.next
        } while cursor != nil && all.count < 2000
        return (all, present, total)
    }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let result = try await fetch(client, campId, filter: filter)
            rows = result.entries.map(Self.row)
            present = result.present
            total = result.total
            loaded()
            if groups.isEmpty, let list = try? await client.campGroups(campId: campId) { groups = list.groups.sorted { ($0.order, $0.name) < ($1.order, $1.name) } }
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !rows.isEmpty)
        }
    }

    /// Ticks or unticks at once and tells the server; the list is read again afterwards, so the ticks of others show too.
    func toggle(_ row: Row) async {
        guard rights.ticks, let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let checked = !rows[index].checked
        snapshot = nil
        rows[index].checked = checked
        let result = await write { client, campId in
            try await client.setCampCount(campId: campId, checked: checked, participantIds: row.participantId.map { [$0] }, personIds: row.personId.map { [$0] })
        }
        guard let changed = result else {
            if let back = rows.firstIndex(where: { $0.id == row.id }) { rows[back].checked = !checked }
            return
        }
        if changed == 0 {
            // Somebody else had set it already: nothing changed here, and the person is told.
            show(Notice(title: checked ? String(localized: "Schon abgehakt.") : String(localized: "Schon entfernt."),
                        message: String(localized: "Jemand war schneller. Die Liste ist aktuell.")))
        }
        await load()
    }

    /// Clears every tick for everybody. The screen asked the person before.
    func reset() async {
        guard rights.resets, let client = active.client, let campId = active.camp?.id else { return }
        let before: Snapshot
        do {
            let all = try await fetch(client, campId, filter: CampCountFilter()).entries.filter(\.checked)
            before = Snapshot(participantIds: all.compactMap(\.participantId), personIds: all.compactMap(\.personId))
        } catch {
            self.error = CampPhase(error: error).failureText
            return
        }
        guard await write({ try await $0.resetCampCount(campId: $1) }) != nil else { return }
        snapshot = before.isEmpty ? nil : before
        show(Notice(title: String(localized: "Liste zurückgesetzt."), message: String(localized: "Alle Haken sind entfernt.")))
        await load()
    }

    func undoReset() async {
        guard rights.resets, let snapshot else { return }
        self.snapshot = nil
        notice = nil
        _ = await write { client, campId in
            try await client.setCampCount(campId: campId, checked: true, participantIds: snapshot.participantIds.isEmpty ? nil : snapshot.participantIds,
                                          personIds: snapshot.personIds.isEmpty ? nil : snapshot.personIds)
        }
        await load()
    }

    override func dismissNotice() {
        super.dismissNotice()
        snapshot = nil
    }
}
