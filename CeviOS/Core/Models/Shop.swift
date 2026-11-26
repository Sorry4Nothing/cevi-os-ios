import Foundation

// MARK: Lädeli (`GET /api/v1/laden`)

/// How an article is sized: one size for all, or a list the person chooses from.
nonisolated enum ShopSizeKind: String, Decodable, Sendable {
    case single = "einheit"
    case list = "liste"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ShopSizeKind(rawValue: value) ?? .unknown
    }
}

/// An article of the shop. `mediumId` (picture) stays unused: the app shows no article pictures.
nonisolated struct ShopArticle: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    /// 0 means free.
    let priceCents: Int
    let sizeKind: ShopSizeKind
    /// Empty for a single size, else at least two.
    let variants: [String]
    /// Sizes of `variants` that cannot be had. They stay visible but cannot be ordered.
    let unavailableVariants: [String]
    let note: String?
    let isAvailable: Bool
    let mediumId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, note = "hinweis", mediumId
        case priceCents = "preisRappen", sizeKind = "groessenart", variants = "varianten"
        case unavailableVariants = "nichtVerfuegbar", isAvailable = "verfuegbar"
    }

    /// The sizes the person may pick.
    var orderableVariants: [String] { variants.filter { !unavailableVariants.contains($0) } }
    var hasSizeList: Bool { sizeKind == .list && !variants.isEmpty }
}

nonisolated struct ShopLimits: Decodable, Equatable, Sendable {
    /// Most lines per order.
    let lines: Int
    /// Most pieces per line.
    let quantity: Int
    /// Most open or ready orders per person.
    let openOrders: Int

    enum CodingKeys: String, CodingKey { case lines = "positionen", quantity = "menge", openOrders = "offeneBestellungen" }
}

/// Rules and texts of the department.
nonisolated struct ShopSettings: Decodable, Equatable, Sendable {
    /// Off: the articles show, but no order is taken.
    let ordersOpen: Bool
    /// Minimum order in cents; 0 means none.
    let minimumCents: Int
    let paymentNote: String
    let paymentMethod: String
    /// Message after ordering; `{uebergabe}` stands for the chosen way of handover.
    let confirmation: String
    let handoverNote: String
    /// Terms, one paragraph per line.
    let terms: String
    let closedText: String

    enum CodingKeys: String, CodingKey {
        case ordersOpen = "bestellenOffen", minimumCents = "mindestRappen", paymentNote = "bezahlhinweis", paymentMethod = "zahlungsart"
        case confirmation = "bestaetigung", handoverNote = "uebergabehinweis", terms = "bedingungen", closedText = "geschlossenText"
    }
}

nonisolated struct ShopCatalog: Decodable, Equatable, Sendable {
    let articles: [ShopArticle]
    /// Ways of handover, to choose one from.
    let handovers: [String]
    let limits: ShopLimits
    let settings: ShopSettings

    enum CodingKeys: String, CodingKey { case articles = "artikel", handovers = "uebergabearten", limits = "grenzen", settings = "einstellungen" }
}

// MARK: Orders

/// `uebergeben` and `storniert` are final.
nonisolated enum ShopOrderStatus: String, Decodable, Sendable {
    case open = "offen"
    case ready = "bereit"
    case handedOver = "uebergeben"
    case cancelled = "storniert"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ShopOrderStatus(rawValue: value) ?? .unknown
    }
}

/// A line as it was when ordered: name and price do not change later.
nonisolated struct ShopOrderLine: Decodable, Equatable, Sendable {
    /// `nil` if the article was deleted since.
    let articleId: UUID?
    let name: String
    let variant: String?
    let quantity: Int
    let unitPriceCents: Int

    enum CodingKeys: String, CodingKey { case articleId = "artikelId", name, variant = "variante", quantity = "menge", unitPriceCents = "einzelpreisRappen" }
}

nonisolated struct ShopOrder: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: ShopOrderStatus
    let handover: String
    let totalCents: Int
    let createdAt: Date
    let changedAt: Date
    let lines: [ShopOrderLine]

    enum CodingKeys: String, CodingKey {
        case id, status, handover = "uebergabe", totalCents = "summeRappen", createdAt = "erstelltAm", changedAt = "geaendertAm", lines = "positionen"
    }
}

nonisolated struct ShopOrderPage: Decodable, Equatable, Sendable {
    let orders: [ShopOrder]
    let hasMore: Bool
    let next: UUID?

    enum CodingKeys: String, CodingKey { case orders = "bestellungen", hasMore = "weitere", next = "naechste" }
}

/// Body of an order. The server reads names and prices itself; `expectedTotalCents` is the sum the person saw.
nonisolated struct ShopOrderCreate: Encodable, Equatable, Sendable {
    struct Line: Encodable, Equatable, Sendable {
        var articleId: UUID
        /// Needed for an article with a size list, forbidden for a single size.
        var variant: String?
        var quantity: Int

        enum CodingKeys: String, CodingKey { case articleId = "artikelId", variant = "variante", quantity = "menge" }
    }

    var lines: [Line]
    var handover: String
    var expectedTotalCents: Int?

    enum CodingKeys: String, CodingKey { case lines = "positionen", handover = "uebergabe", expectedTotalCents = "erwarteteSummeRappen" }
}

// MARK: Error bodies

/// Extra fields of the 409 and 422 answers of an order.
nonisolated struct ShopConflict: Decodable, Equatable, Sendable {
    let code: String?
    let message: String?
    /// `ARTIKEL_NICHT_VERFUEGBAR`.
    let articleIds: [UUID]?
    /// `PREIS_GEAENDERT`: the sum of the server.
    let totalCents: Int?
    /// `MINDESTBESTELLUNG`.
    let minimumCents: Int?
    /// `GROESSE_NICHT_VERFUEGBAR`.
    let lines: [Line]?

    struct Line: Decodable, Equatable, Sendable {
        let articleId: UUID
        let variant: String
        enum CodingKeys: String, CodingKey { case articleId = "artikelId", variant = "variante" }
    }

    enum CodingKeys: String, CodingKey {
        case code, message, articleIds = "artikelIds", totalCents = "summeRappen", minimumCents = "mindestRappen", lines = "positionen"
    }
}
