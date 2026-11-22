import Foundation

// MARK: Shopping list (Einkauf)

/// The department of the shop. The app groups the list by it. The server sets it from the name if the request has none.
nonisolated enum CampShoppingGroup: String, CampTolerantEnum, CaseIterable {
    case produce = "obst_gemuese"
    case bread = "brot"
    case dairy = "milch_kaese"
    case meat = "fleisch_fisch"
    case pantry = "vorrat"
    case drinks = "getraenke"
    case household = "haushalt"
    case other = "diverses"
    case unknown

    static var fallback: Self { .unknown }

    var title: String {
        switch self {
        case .produce: String(localized: "Obst und Gemüse")
        case .bread: String(localized: "Brot")
        case .dairy: String(localized: "Milch und Käse")
        case .meat: String(localized: "Fleisch und Fisch")
        case .pantry: String(localized: "Vorrat")
        case .drinks: String(localized: "Getränke")
        case .household: String(localized: "Haushalt")
        case .other, .unknown: String(localized: "Diverses")
        }
    }
}

nonisolated struct CampShoppingBuyer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let ceviName: String?
}

nonisolated struct CampShoppingItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let name: String
    /// Positive, up to three decimals; `nil` without an amount.
    let amount: Double?
    /// Lower case; `nil` without a unit.
    let unit: String?
    let group: CampShoppingGroup
    let buyerPersonId: UUID?
    let buyer: CampShoppingBuyer?
    /// Ticked off while shopping.
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case id, version, name, amount = "menge", unit = "einheit", group = "warengruppe"
        case buyerPersonId = "einkaeuferPersonId", buyer = "einkaeufer", done = "erledigt"
    }
}

nonisolated struct CampShoppingPage: Codable, Equatable, Sendable {
    let items: [CampShoppingItem]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case items = "artikel", next = "naechster" }

    /// The items by department, in the order of `CampShoppingGroup.allCases`; empty departments are left out.
    var byGroup: [(group: CampShoppingGroup, items: [CampShoppingItem])] {
        CampShoppingGroup.allCases.compactMap { group in
            let rows = items.filter { $0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }
}

/// Who buys: the signed-in person (`ich`) or a member of the camp. The filters combine with `done`.
nonisolated enum CampShoppingBuyerFilter: Equatable, Sendable {
    case me
    case person(UUID)

    var queryValue: String {
        switch self {
        case .me: "ich"
        case .person(let id): id.uuidString.lowercased()
        }
    }
}

nonisolated struct CampShoppingRef: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
}

/// Equal items in one row with the amounts added (same name, unit, buyer and state; amounts of different units are never added).
nonisolated struct CampShoppingTotal: Codable, Equatable, Sendable {
    let name: String
    /// `nil` if no item of the row has an amount.
    let amount: Double?
    let unit: String?
    let group: CampShoppingGroup
    let buyerPersonId: UUID?
    let buyer: CampShoppingBuyer?
    let done: Bool
    /// How many items are in the row.
    let count: Int
    let entries: [CampShoppingRef]

    enum CodingKeys: String, CodingKey {
        case name, amount = "menge", unit = "einheit", group = "warengruppe", buyerPersonId = "einkaeuferPersonId"
        case buyer = "einkaeufer", done = "erledigt", count = "anzahl", entries = "eintraege"
    }
}

nonisolated struct CampShoppingTotalPage: Codable, Equatable, Sendable {
    let items: [CampShoppingTotal]
    let next: UUID?

    enum CodingKeys: String, CodingKey { case items = "artikel", next = "naechster" }
}

/// A name the camp used before, most used first, for suggestions while typing.
nonisolated struct CampShoppingSuggestion: Codable, Equatable, Sendable {
    let name: String
    /// How often an item with this name was created in the camp.
    let frequency: Int

    enum CodingKeys: String, CodingKey { case name, frequency = "haeufigkeit" }
}

nonisolated struct CampShoppingSuggestionList: Codable, Equatable, Sendable {
    let suggestions: [CampShoppingSuggestion]

    enum CodingKeys: String, CodingKey { case suggestions = "vorschlaege" }
}

nonisolated struct CampShoppingCreate: Encodable, Sendable {
    /// Up to 100 characters.
    var name: String
    var amount: Double?
    var unit: String?
    /// Without it the server takes the department it knows for the name.
    var group: CampShoppingGroup?
    /// A member of the camp, else 400 `KEIN_MITGLIED`.
    var buyerPersonId: UUID?

    enum CodingKeys: String, CodingKey { case name, amount = "menge", unit = "einheit", group = "warengruppe", buyerPersonId = "einkaeuferPersonId" }
}

/// Ticking off is one update: `CampShoppingPatch(version:, done: true)`.
nonisolated struct CampShoppingPatch: Encodable, Sendable {
    let version: Int
    var name: String?
    var amount: CampField<Double>?
    var unit: CampField<String>?
    var group: CampShoppingGroup?
    var buyerPersonId: CampField<UUID>?
    var done: Bool?

    enum CodingKeys: String, CodingKey {
        case version, name, amount = "menge", unit = "einheit", group = "warengruppe", buyerPersonId = "einkaeuferPersonId", done = "erledigt"
    }
}

// MARK: Packing list (Packliste)

/// The state of a point in the own copy of the list.
nonisolated enum CampPackingState: String, Codable, Sendable {
    case open = "offen"
    case checked = "abgehakt"
    /// The person took the point off the own list.
    case removed = "entfernt"
}

/// A point of the template of the camp leadership. `state` is the own state; it is missing in the answer to writing the template.
nonisolated struct CampPackingPoint: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let section: String
    let text: String
    /// Only for roles that may read confidential points.
    let leadershipOnly: Bool
    let order: Int
    let state: CampPackingState?

    enum CodingKeys: String, CodingKey {
        case id, version, text, section = "abschnitt", leadershipOnly = "nurLagerleitung", order = "reihenfolge", state = "zustand"
    }
}

/// A point the person added. Only the person sees it, not even the camp leadership. No version: nobody else writes it.
nonisolated struct CampOwnPackingPoint: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let section: String
    let text: String
    let checked: Bool
    let order: Int

    enum CodingKeys: String, CodingKey { case id, text, section = "abschnitt", checked = "abgehakt", order = "reihenfolge" }
}

/// The own copy of the packing list: the template with the own state, and the own points.
nonisolated struct CampPackingList: Codable, Equatable, Sendable {
    let points: [CampPackingPoint]
    let own: [CampOwnPackingPoint]

    enum CodingKeys: String, CodingKey { case points = "punkte", own = "eigene" }
}

nonisolated struct CampPackingStateBody: Codable, Equatable, Sendable {
    let state: CampPackingState

    enum CodingKeys: String, CodingKey { case state = "zustand" }
}

nonisolated struct CampPackingStateResult: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let state: CampPackingState

    enum CodingKeys: String, CodingKey { case id, state = "zustand" }
}

nonisolated struct CampPackingPointCreate: Encodable, Sendable {
    /// Up to 100 characters.
    var section: String
    /// Up to 300 characters.
    var text: String
    var leadershipOnly: Bool?
    var order: Int?

    enum CodingKeys: String, CodingKey { case text, section = "abschnitt", leadershipOnly = "nurLagerleitung", order = "reihenfolge" }
}

nonisolated struct CampPackingPointPatch: Encodable, Sendable {
    let version: Int
    var section: String?
    var text: String?
    var leadershipOnly: Bool?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, text, section = "abschnitt", leadershipOnly = "nurLagerleitung", order = "reihenfolge" }
}

nonisolated struct CampOwnPackingPointCreate: Encodable, Sendable {
    var section: String
    var text: String
    var order: Int?

    enum CodingKeys: String, CodingKey { case text, section = "abschnitt", order = "reihenfolge" }
}

nonisolated struct CampOwnPackingPointPatch: Encodable, Sendable {
    var section: String?
    var text: String?
    var order: Int?
    var checked: Bool?

    enum CodingKeys: String, CodingKey { case text, section = "abschnitt", order = "reihenfolge", checked = "abgehakt" }
}
