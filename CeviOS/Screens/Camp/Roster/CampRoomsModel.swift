import SwiftUI

/// L20: rooms and tents. The camp leadership places and removes people; the team sees names only.
@MainActor @Observable
final class CampRoomsModel: CampRosterModel {
    struct Member: Equatable, Identifiable {
        let id: UUID
        let kind: CampRoomOccupantKind
        let name: String
    }

    struct Row: Equatable, Identifiable {
        let id: UUID
        let name: String
        let kind: CampRoomKind
        let note: String?
        /// `nil` in the short shape of the team.
        let places: Int?
        let occupied: Int?
        let overbooked: Bool
        let members: [Member]

        var isFull: Bool { places.map { $0 > 0 && (occupied ?? 0) == $0 } ?? false }
        var kindName: String { kind == .tent ? String(localized: "Zelt") : String(localized: "Zimmer") }
        /// «Zimmer, 1. Stock».
        var detail: String { [kindName, note].compactMap(CampRosterText.trimmed).joined(separator: ", ") }
    }

    var rows: [Row] = []
    /// People without a room (leads only).
    var openCount = 0

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let list = try await client.campRooms(campId: campId)
            rows = list.rooms.map(Self.row)
            openCount = list.open.map { $0.participants + $0.team } ?? 0
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !rows.isEmpty)
        }
    }

    static func row(_ view: CampRoomView) -> Row {
        switch view {
        case .full(let room):
            Row(id: room.id, name: room.name, kind: room.kind, note: room.note, places: room.places, occupied: room.occupied, overbooked: room.overbooked,
                members: room.members.map { Member(id: $0.id, kind: $0.kind, name: $0.name) })
        case .team(let room):
            Row(id: room.id, name: room.name, kind: room.kind, note: nil, places: nil, occupied: nil, overbooked: false,
                members: room.members.map { Member(id: UUID(), kind: .unknown, name: $0.name) })
        }
    }

    /// The people without a room: participants and team members.
    func loadOpenPeople() async {
        await loadChoices { client, campId in
            var result: [CampPersonChoice] = []
            for kind in [CampPeopleKind.participants, .team] {
                var cursor: UUID?
                var count = 0
                repeat {
                    let page = try await client.campOpenRoomPeople(campId: campId, kind: kind, after: cursor, limit: 100)
                    result += page.entries.map { entry in
                        let name = kind == .team ? entry.name : (CampRosterText.fullName(first: entry.firstName, last: entry.lastName) ?? entry.name)
                        return CampPersonChoice(id: entry.id, isParticipant: kind == .participants,
                                                label: CampRosterText.label(name: name, ceviName: entry.ceviName), detail: entry.level)
                    }
                    count += page.entries.count
                    cursor = page.next
                } while cursor != nil && count < 1000
            }
            return result
        }
    }

    func place(_ people: [CampPersonChoice], in roomId: UUID) async {
        guard rights.placesPeople, !people.isEmpty, let room = rows.first(where: { $0.id == roomId }) else { return }
        let participants = people.filter(\.isParticipant).map(\.id)
        let team = people.filter { !$0.isParticipant }.map(\.id)
        let body = CampRoomPeople(participantIds: participants.isEmpty ? nil : participants, personIds: team.isEmpty ? nil : team)
        guard let result = await write({ try await $0.placeInCampRoom(campId: $1, roomId: roomId, body) }) else { return }
        let title = people.count == 1 ? String(localized: "\(people[0].label) ist jetzt in \(room.name).") : String(localized: "\(people.count) Personen eingeteilt.")
        show(Notice(title: title, message: result.overbooked ? String(localized: "\(room.name) ist überbelegt: \(result.occupied) von \(result.places).") : nil))
        await load()
    }

    func remove(_ member: Member, from roomId: UUID) async {
        guard rights.placesPeople, let room = rows.first(where: { $0.id == roomId }) else { return }
        let body: CampRoomPeople
        switch member.kind {
        case .participant: body = CampRoomPeople(participantIds: [member.id], personIds: nil)
        case .person: body = CampRoomPeople(participantIds: nil, personIds: [member.id])
        case .unknown: return
        }
        guard await write({ try await $0.removeFromCampRoom(campId: $1, roomId: roomId, body) }) != nil else { return }
        show(Notice(title: String(localized: "\(member.name) ist nicht mehr in \(room.name).")))
        await load()
    }
}
