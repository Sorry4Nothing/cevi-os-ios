import Foundation

extension APIClient {
    /// Articles, ways of handover, limits and rules of the own department. 401 without a session.
    func shopCatalog() async throws -> ShopCatalog {
        try await load("GET", "/api/v1/laden")
    }

    /// The own orders in every state, newest first. `after` is `next` of the previous page.
    func myShopOrders(after: UUID? = nil, limit: Int = 50) async throws -> ShopOrderPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: after.uuidString.lowercased())) }
        return try await load("GET", "/api/v1/laden/bestellungen/meine", query: query)
    }

    /// Orders once: the contract has no key against double orders, so the caller never repeats this on its own.
    /// 409 `LADEN_GESCHLOSSEN`, `MINDESTBESTELLUNG`, `ARTIKEL_NICHT_VERFUEGBAR`, `PREIS_GEAENDERT`, `BESTELL_LIMIT`;
    /// 422 `GROESSE_NICHT_VERFUEGBAR`; 400 with a code and text. Read them with `ShopRules.orderFailure`.
    func createShopOrder(_ body: ShopOrderCreate) async throws -> ShopOrder {
        try await load("POST", "/api/v1/laden/bestellungen", body: body)
    }

    /// Only the own order, only while it is `offen`. 204 again for an order already cancelled; 409 `STATUS_UNGUELTIG` once ready or handed over.
    func cancelShopOrder(id: UUID) async throws {
        try await send("DELETE", "/api/v1/laden/bestellungen/\(id.uuidString.lowercased())")
    }
}

/// Codes, texts and amounts of the shop.
nonisolated enum ShopRules {
    static let closedCode = "LADEN_GESCHLOSSEN"
    static let minimumCode = "MINDESTBESTELLUNG"
    static let articleUnavailableCode = "ARTIKEL_NICHT_VERFUEGBAR"
    static let sizeUnavailableCode = "GROESSE_NICHT_VERFUEGBAR"
    static let priceChangedCode = "PREIS_GEAENDERT"
    static let orderLimitCode = "BESTELL_LIMIT"
    static let tooManyLinesCode = "POSITIONEN_ZU_VIELE"
    static let quantityTooHighCode = "MENGE_ZU_GROSS"
    static let variantInvalidCode = "VARIANTE_UNGUELTIG"
    static let handoverUnknownCode = "UEBERGABE_UNBEKANNT"
    static let statusInvalidCode = "STATUS_UNGUELTIG"

    /// «CHF 12.50», from cents.
    static func chf(_ cents: Int) -> String {
        "CHF \(cents / 100).\(String(format: "%02d", cents % 100))"
    }

    /// The price of an article: «Gratis» or «CHF 12.50».
    static func price(_ cents: Int) -> String { cents == 0 ? String(localized: "Gratis") : chf(cents) }

    /// The message after ordering: `{uebergabe}` becomes the chosen way. An empty text of the department falls back to a short line.
    static func confirmation(_ template: String, handover: String) -> String {
        let text = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return String(localized: "Deine Bestellung ist eingegangen. Übergabe: \(handover).") }
        return text.replacingOccurrences(of: "{uebergabe}", with: handover)
    }

    /// What a failed order means for the cart and for the person.
    struct OrderFailure: Equatable {
        var text: String
        /// Articles to take out of the cart (no longer to be had).
        var removeArticles: Set<UUID> = []
        /// Sizes to take out of the cart.
        var removeSizes: [ShopConflict.Line] = []
        /// The shop changed (prices, sizes, closed): load it again.
        var reloadsCatalog = false
        /// The network failed, so the order may have arrived. The text says so.
        var maybeSent = false
    }

    static func orderFailure(_ error: APIError) -> OrderFailure {
        if error.kind == .network {
            return OrderFailure(text: String(localized: "Keine Verbindung zum Server. Vielleicht ist die Bestellung angekommen: Schau unter «Meine Bestellungen» nach, bevor du nochmals bestellst."), maybeSent: true)
        }
        let body = error.conflictBody.flatMap { try? JSONDecoder.api.decode(ShopConflict.self, from: $0) }
        switch (error.kind, error.code) {
        case (.conflict, closedCode):
            return OrderFailure(text: nonEmpty(error.message) ?? String(localized: "Das Lädeli nimmt im Moment keine Bestellungen an."), reloadsCatalog: true)
        case (.conflict, minimumCode):
            let minimum = body?.minimumCents.map { String(localized: "Die Mindestbestellung ist \(chf($0)).") }
            return OrderFailure(text: minimum ?? String(localized: "Die Bestellung ist zu klein. Lege noch etwas in den Warenkorb."))
        case (.conflict, articleUnavailableCode):
            return OrderFailure(text: String(localized: "Mindestens ein Artikel ist nicht mehr zu haben. Wir haben ihn aus dem Warenkorb genommen. Prüfe die Summe und bestelle nochmals."), removeArticles: Set(body?.articleIds ?? []), reloadsCatalog: true)
        case (.conflict, priceChangedCode):
            let total = body?.totalCents.map { String(localized: "Die neue Summe ist \(chf($0)).") } ?? ""
            return OrderFailure(text: String(localized: "Ein Preis hat sich geändert. \(total) Prüfe den Warenkorb und bestelle nochmals."), reloadsCatalog: true)
        case (.conflict, orderLimitCode):
            return OrderFailure(text: String(localized: "Du hast schon so viele offene Bestellungen, wie die Abteilung erlaubt. Warte, bis eine übergeben ist, oder storniere eine."))
        case (.invalidInput, tooManyLinesCode):
            return OrderFailure(text: String(localized: "Der Warenkorb hat zu viele Positionen. Nimm einige heraus."))
        case (.invalidInput, quantityTooHighCode):
            return OrderFailure(text: String(localized: "Von einem Artikel ist die Menge zu gross. Verkleinere sie."))
        case (.invalidInput, variantInvalidCode):
            return OrderFailure(text: String(localized: "Eine Grösse stimmt nicht mehr. Lade das Lädeli neu und wähle sie nochmals."), reloadsCatalog: true)
        case (.invalidInput, handoverUnknownCode):
            return OrderFailure(text: String(localized: "Diese Übergabe gibt es nicht mehr. Wähle eine andere."), reloadsCatalog: true)
        case (.server, _) where error.status == 422 && error.code == sizeUnavailableCode:
            return OrderFailure(text: nonEmpty(error.message) ?? String(localized: "Eine Grösse ist nicht mehr zu haben. Wir haben sie aus dem Warenkorb genommen."), removeSizes: body?.lines ?? [], reloadsCatalog: true)
        case (.unauthorized, _):
            return OrderFailure(text: String(localized: "Du bist nicht mehr angemeldet."))
        case (.rateLimited, _):
            return OrderFailure(text: error.displayText)
        default:
            return OrderFailure(text: error.displayText)
        }
    }

    /// Text of a failed cancellation.
    static func cancelError(_ error: APIError) -> String {
        switch error.kind {
        case .conflict where error.code == statusInvalidCode:
            String(localized: "Die Abteilung hat die Bestellung schon bereitgestellt. Du kannst sie nicht mehr stornieren.")
        case .notFound:
            String(localized: "Diese Bestellung gibt es nicht mehr.")
        default:
            error.displayText
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
