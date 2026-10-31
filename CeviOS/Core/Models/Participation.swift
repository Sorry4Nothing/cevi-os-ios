import Foundation

/// Answer including "open" (no answer yet), as the overviews report it.
nonisolated enum OverviewAnswer: String, Decodable, Sendable {
    case yes = "ja"
    case no = "nein"
    case open = "offen"
}

nonisolated struct ParticipationCounts: Decodable, Equatable, Sendable {
    let yes: Int
    let no: Int
    let open: Int

    enum CodingKeys: String, CodingKey { case yes = "ja", no = "nein", open = "offen" }
}

nonisolated struct ParticipationChild: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let unitId: UUID
    let answer: OverviewAnswer

    enum CodingKeys: String, CodingKey {
        case id, firstName = "vorname", lastName = "nachname", unitId = "stufeId", answer = "status"
    }
}

nonisolated struct ParticipationLeader: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let unitId: UUID
    let role: RoleType
    let answer: OverviewAnswer

    enum CodingKeys: String, CodingKey {
        case id, name, ceviName, unitId = "stufeId", role = "rolle", answer = "status"
    }
}

/// `GET /programme/{id}/teilnahmen`. The server computes the numbers; the app does not recount.
nonisolated struct ParticipationOverview: Decodable, Equatable, Sendable {
    struct Totals: Decodable, Equatable, Sendable {
        let children: ParticipationCounts
        let leaders: ParticipationCounts

        enum CodingKeys: String, CodingKey { case children = "kinder", leaders = "leitende" }
    }

    let totals: Totals
    let children: [ParticipationChild]
    let leaders: [ParticipationLeader]

    enum CodingKeys: String, CodingKey { case totals = "zahlen", children = "kinder", leaders = "leitende" }
}

/// Order of the participation lists: open first, then yes, then no; by name within each group.
nonisolated enum ParticipationOrder {
    static func sorted<T>(_ items: [T], answer: (T) -> OverviewAnswer, name: (T) -> String) -> [T] {
        items.sorted { a, b in
            let (ra, rb) = (rank(answer(a)), rank(answer(b)))
            if ra != rb { return ra < rb }
            return name(a).localizedStandardCompare(name(b)) == .orderedAscending
        }
    }

    private static func rank(_ answer: OverviewAnswer) -> Int {
        switch answer {
        case .open: 0
        case .yes: 1
        case .no: 2
        }
    }
}
