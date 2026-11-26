import Foundation
import Testing
@testable import CeviOS

private nonisolated let shirt = "0190a000-0000-7000-8000-0000000c0001"
private nonisolated let bottle = "0190a000-0000-7000-8000-0000000c0002"
private nonisolated let orderId = "0190a000-0000-7000-8000-0000000d0001"

private nonisolated func catalogJSON(open: Bool = true, minimum: Int = 0, handovers: String = #""Im Pfadiheim","Am Lager""#, shirtSizes: String = #"["S","M","L"]"#, unavailable: String = #"["L"]"#) -> String {
    """
    {"angemeldetAls":null,"artikel":[
     {"id":"\(shirt)","name":"Lagershirt","preisRappen":2500,"mediumId":null,"groessenart":"liste","varianten":\(shirtSizes),"nichtVerfuegbar":\(unavailable),"hinweis":null,"verfuegbar":true,"verfuegbarGesetzt":true,"reihenfolge":1},
     {"id":"\(bottle)","name":"Trinkflasche","preisRappen":1250,"mediumId":null,"groessenart":"einheit","varianten":[],"nichtVerfuegbar":[],"hinweis":"Mit Deckel","verfuegbar":true,"verfuegbarGesetzt":true,"reihenfolge":2}],
     "uebergabearten":[\(handovers)],"grenzen":{"positionen":2,"menge":3,"offeneBestellungen":5},
     "einstellungen":{"bestellenOffen":\(open),"schnellDazu":true,"preiseOeffentlich":true,"maxMenge":3,"maxPositionen":2,"maxOffene":5,"mindestRappen":\(minimum),
      "bezahlhinweis":"Bar bei der Übergabe.","zahlungsart":"Bar","bestaetigung":"Danke, Übergabe: {uebergabe}.","uebergabehinweis":"","bedingungen":"Eins\\nZwei","geschlossenText":"Zu bis zum Lager."}}
    """
}
private nonisolated func orderJSON(_ id: String = orderId, status: String = "offen") -> String {
    """
    {"id":"\(id)","status":"\(status)","uebergabe":"Am Lager","summeRappen":6250,"erstelltAm":"2027-03-01T08:00:00Z","geaendertAm":"2027-03-01T08:00:00Z",
     "positionen":[{"artikelId":"\(shirt)","name":"Lagershirt","variante":"M","menge":2,"einzelpreisRappen":2500},{"artikelId":null,"name":"Trinkflasche","variante":null,"menge":1,"einzelpreisRappen":1250}]}
    """
}
private nonisolated func newHost() -> String { "s\(UUID().uuidString.prefix(8).lowercased()).test.example.org" }
private nonisolated func client(_ host: String) -> APIClient {
    APIClient(baseURL: URL(string: "https://\(host)")!, appVersion: "1.0.0", cookieStore: InMemoryCookieStore(["s": "1"]),
              session: APIClient.makeSession(protocolClasses: [StubProtocol.self]))
}
private nonisolated func error(_ status: Int, _ body: String) -> APIError { APIError.from(status: status, data: Data(body.utf8)) }
private nonisolated func decode(_ json: String) -> ShopCatalog { try! JSONDecoder.api.decode(ShopCatalog.self, from: Data(json.utf8)) }

/// Serves the shop; `answer` is the reply to a `POST` (order) and `DELETE` (cancel).
private nonisolated func serve(_ host: String, catalog: String = catalogJSON(), orders: String? = nil, answer: @escaping @Sendable () -> (Int, String) = { (201, orderJSON()) }) {
    StubProtocol.register(host: host) { request in
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/api/v1/laden"): return (200, [:], Data(catalog.utf8))
        case ("GET", "/api/v1/laden/bestellungen/meine"):
            return (200, [:], Data((orders ?? #"{"bestellungen":[\#(orderJSON())],"weitere":false,"naechste":null}"#).utf8))
        default:
            let (status, body) = answer()
            return (status, [:], Data(body.utf8))
        }
    }
}

private nonisolated func sentBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(StubProtocol.body(of: request))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

struct ShopTests {
    // MARK: Service

    @Test func readsTheCatalog() async throws {
        let host = newHost()
        serve(host)
        let catalog = try await client(host).shopCatalog()
        #expect(catalog.articles.count == 2 && catalog.handovers == ["Im Pfadiheim", "Am Lager"])
        #expect(catalog.articles[0].hasSizeList && catalog.articles[0].orderableVariants == ["S", "M"] && catalog.articles[0].unavailableVariants == ["L"])
        #expect(catalog.articles[1].sizeKind == .single && catalog.articles[1].note == "Mit Deckel")
        #expect(catalog.limits == ShopLimits(lines: 2, quantity: 3, openOrders: 5) && catalog.settings.ordersOpen)
        #expect(StubProtocol.requests(host: host).first?.url?.path == "/api/v1/laden")
    }

    @Test func readsOrdersWithPaging() async throws {
        let host = newHost()
        serve(host)
        let page = try await client(host).myShopOrders(after: UUID(uuidString: orderId))
        #expect(page.orders.count == 1 && page.orders[0].status == .open && page.orders[0].lines[1].articleId == nil && !page.hasMore)
        let url = try #require(StubProtocol.requests(host: host).first?.url)
        #expect(url.path == "/api/v1/laden/bestellungen/meine")
        #expect(url.query?.contains("limit=50") == true && url.query?.contains("nach=\(orderId)") == true)
    }

    @Test func orderBodyHasNoPricesButTheExpectedSum() async throws {
        let host = newHost()
        serve(host)
        let body = ShopOrderCreate(lines: [.init(articleId: UUID(uuidString: shirt)!, variant: "M", quantity: 2), .init(articleId: UUID(uuidString: bottle)!, variant: nil, quantity: 1)], handover: "Am Lager", expectedTotalCents: 6250)
        let order = try await client(host).createShopOrder(body)
        #expect(order.totalCents == 6250 && order.handover == "Am Lager")
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/v1/laden/bestellungen")
        let sent = try sentBody(request)
        #expect(Set(sent.keys) == ["positionen", "uebergabe", "erwarteteSummeRappen"] && sent["erwarteteSummeRappen"] as? Int == 6250)
        let lines = try #require(sent["positionen"] as? [[String: Any]])
        #expect(Set(lines[0].keys) == ["artikelId", "variante", "menge"] && lines[1]["variante"] == nil)
    }

    @Test func cancelsAnOrder() async throws {
        let host = newHost()
        serve(host) { (204, "") }
        try await client(host).cancelShopOrder(id: UUID(uuidString: orderId)!)
        let request = try #require(StubProtocol.requests(host: host).first)
        #expect(request.httpMethod == "DELETE" && request.url?.path == "/api/v1/laden/bestellungen/\(orderId)")
    }

    // MARK: Texts

    @Test func amountsShowAsFrancs() {
        #expect(ShopRules.chf(1250) == "CHF 12.50" && ShopRules.chf(5) == "CHF 0.05" && ShopRules.chf(0) == "CHF 0.00" && ShopRules.chf(100000) == "CHF 1000.00")
        #expect(ShopRules.price(0) == "Gratis" && ShopRules.price(300) == "CHF 3.00")
        #expect(ShopRules.confirmation("Hol es {uebergabe} ab.", handover: "am Lager") == "Hol es am Lager ab.")
        #expect(ShopRules.confirmation("  ", handover: "am Lager").contains("am Lager"))
    }

    @Test func everyOrderErrorHasAText() {
        let id = UUID(uuidString: bottle)!
        let closed = ShopRules.orderFailure(error(409, #"{"code":"LADEN_GESCHLOSSEN","message":"Zu bis zum Lager."}"#))
        #expect(closed.text == "Zu bis zum Lager." && closed.reloadsCatalog)
        #expect(ShopRules.orderFailure(error(409, #"{"code":"MINDESTBESTELLUNG","message":"x","mindestRappen":1500}"#)).text == "Die Mindestbestellung ist CHF 15.00.")
        let gone = ShopRules.orderFailure(error(409, #"{"code":"ARTIKEL_NICHT_VERFUEGBAR","message":"x","artikelIds":["\#(bottle)"]}"#))
        #expect(gone.removeArticles == [id] && gone.reloadsCatalog)
        let price = ShopRules.orderFailure(error(409, #"{"code":"PREIS_GEAENDERT","message":"x","summeRappen":6300}"#))
        #expect(price.text.contains("CHF 63.00") && price.reloadsCatalog)
        #expect(ShopRules.orderFailure(error(409, #"{"code":"BESTELL_LIMIT","message":"x"}"#)).text.contains("offene Bestellungen"))
        #expect(ShopRules.orderFailure(error(400, #"{"code":"POSITIONEN_ZU_VIELE","message":"x"}"#)).text.contains("zu viele Positionen"))
        #expect(ShopRules.orderFailure(error(400, #"{"code":"MENGE_ZU_GROSS","message":"x"}"#)).text.contains("Menge"))
        #expect(ShopRules.orderFailure(error(400, #"{"code":"VARIANTE_UNGUELTIG","message":"x"}"#)).reloadsCatalog)
        #expect(ShopRules.orderFailure(error(400, #"{"code":"UEBERGABE_UNBEKANNT","message":"x"}"#)).text.contains("Übergabe"))
        let size = ShopRules.orderFailure(error(422, #"{"code":"GROESSE_NICHT_VERFUEGBAR","feld":"positionen","message":"Lagershirt in M ist nicht mehr zu haben.","positionen":[{"artikelId":"\#(shirt)","variante":"M"}]}"#))
        #expect(size.text == "Lagershirt in M ist nicht mehr zu haben." && size.removeSizes.first?.variant == "M")
        #expect(ShopRules.orderFailure(error(429, "{}")).text == error(429, "{}").displayText)
        #expect(ShopRules.orderFailure(error(401, "{}")).text.contains("angemeldet"))
        let offline = ShopRules.orderFailure(.network)
        #expect(offline.maybeSent && offline.text.contains("Meine Bestellungen"))
        #expect(ShopRules.cancelError(error(409, #"{"code":"STATUS_UNGUELTIG","message":"x"}"#)).contains("bereitgestellt"))
        #expect(ShopRules.cancelError(error(404, "{}")) == "Diese Bestellung gibt es nicht mehr.")
    }

    // MARK: Cart

    @MainActor private func loaded(_ host: String = newHost(), catalog: String = catalogJSON()) async -> (ShopModel, APIClient) {
        serve(host, catalog: catalog)
        let api = client(host)
        let model = ShopModel()
        await model.load(client: api)
        return (model, api)
    }

    @MainActor @Test func theCartCountsAndKeepsToTheLimits() async throws {
        let (model, _) = await loaded()
        let shirtArticle = model.catalog!.articles[0], bottleArticle = model.catalog!.articles[1]
        model.add(shirtArticle) // no size chosen: nothing
        model.add(shirtArticle, variant: "L") // not to be had: nothing
        #expect(model.cart.isEmpty)
        model.add(shirtArticle, variant: "M"); model.add(shirtArticle, variant: "M"); model.add(shirtArticle, variant: "S")
        #expect(model.cart.count == 2 && model.pieces == 3 && model.totalCents == 7500)
        model.add(bottleArticle) // third line, limit is 2
        #expect(model.cart.count == 2 && model.error?.contains("höchstens 2 Positionen") == true)
        model.add(shirtArticle, variant: "M") // 3 pieces of M, limit 3
        model.add(shirtArticle, variant: "M")
        #expect(model.cart[0].quantity == 3 && model.error?.contains("höchstens 3 Stück") == true)
        model.setQuantity(model.cart[0].id, 9)
        #expect(model.cart[0].quantity == 3)
        model.setQuantity(model.cart[0].id, 0)
        #expect(model.cart.count == 1)
    }

    @MainActor @Test func aClosedShopTakesNoCartAndNoOrder() async {
        let host = newHost()
        let (model, api) = await loaded(host, catalog: catalogJSON(open: false))
        model.add(model.catalog!.articles[1])
        #expect(!model.isOpen && model.cart.isEmpty)
        await model.order(client: api)
        #expect(StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }

    @MainActor @Test func aReloadDropsWhatIsGoneAndPicksTheOnlyHandover() async {
        let host = newHost()
        let (model, api) = await loaded(host, catalog: catalogJSON(handovers: #""Am Lager""#))
        #expect(model.handover == "Am Lager")
        model.add(model.catalog!.articles[0], variant: "M")
        serve(host, catalog: catalogJSON(handovers: #""Am Lager""#, unavailable: #"["M","L"]"#))
        await model.load(client: api)
        #expect(model.cart.isEmpty && model.error != nil)
    }

    @MainActor @Test func theOrderNeedsAHandoverAndTheMinimum() async {
        let host = newHost()
        let (model, api) = await loaded(host, catalog: catalogJSON(minimum: 3000))
        #expect(model.blocker == "Der Warenkorb ist leer.")
        model.add(model.catalog!.articles[1])
        #expect(model.blocker == "Wähle, wie du die Bestellung bekommst.")
        model.handover = "Am Lager"
        #expect(model.blocker == "Die Mindestbestellung ist CHF 30.00.")
        await model.order(client: api)
        #expect(model.error == "Die Mindestbestellung ist CHF 30.00." && StubProtocol.requests(host: host).allSatisfy { $0.httpMethod == "GET" })
    }

    // MARK: Order

    @MainActor @Test func aGoodOrderEmptiesTheCartAndShowsTheMessage() async throws {
        let host = newHost()
        let (model, api) = await loaded(host)
        model.add(model.catalog!.articles[0], variant: "M"); model.add(model.catalog!.articles[1])
        model.handover = "Am Lager"
        await model.order(client: api)
        #expect(model.cart.isEmpty && model.placedText == "Danke, Übergabe: Am Lager." && model.error == nil && !model.isOrdering)
        let post = try #require(StubProtocol.requests(host: host).first { $0.httpMethod == "POST" })
        let sent = try sentBody(post)
        #expect(sent["erwarteteSummeRappen"] as? Int == 3750 && sent["uebergabe"] as? String == "Am Lager")
        model.finishOrder()
        #expect(model.placedText == nil)
    }

    @MainActor @Test func aFailedOrderIsNeverSentTwice() async {
        let host = newHost()
        let (model, api) = await loaded(host)
        model.add(model.catalog!.articles[1]); model.handover = "Am Lager"
        serve(host) { (409, #"{"code":"BESTELL_LIMIT","message":"x"}"#) }
        await model.order(client: api)
        #expect(model.cart.count == 1 && model.placedText == nil && model.error?.contains("offene Bestellungen") == true)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "POST" }.count == 1)
        // The network fails: the cart stays, the text warns, nothing repeats.
        let offline = client(newHost())
        await model.order(client: offline)
        #expect(model.cart.count == 1 && model.error?.contains("Meine Bestellungen") == true)
    }

    @MainActor @Test func aChangedPriceKeepsTheCartAndLoadsTheShopAgain() async {
        let host = newHost()
        let (model, api) = await loaded(host)
        model.add(model.catalog!.articles[1]); model.handover = "Am Lager"
        serve(host) { (409, #"{"code":"PREIS_GEAENDERT","message":"x","summeRappen":1300}"#) }
        await model.order(client: api)
        #expect(model.cart.count == 1 && model.error?.contains("CHF 13.00") == true)
        #expect(StubProtocol.requests(host: host).filter { $0.httpMethod == "GET" }.count == 2)
    }

    @MainActor @Test func aSizeThatWentRemovesItsLine() async {
        let host = newHost()
        let (model, api) = await loaded(host)
        model.add(model.catalog!.articles[0], variant: "M"); model.add(model.catalog!.articles[1]); model.handover = "Am Lager"
        serve(host) { (422, #"{"code":"GROESSE_NICHT_VERFUEGBAR","feld":"positionen","message":"Lagershirt in M ist weg.","positionen":[{"artikelId":"\#(shirt)","variante":"M"}]}"#) }
        await model.order(client: api)
        #expect(model.cart.count == 1 && model.cart[0].articleId == UUID(uuidString: bottle) && model.error == "Lagershirt in M ist weg.")
    }

    // MARK: My orders

    @MainActor @Test func theOrderListLoadsAndOnlyOpenOnesCancel() async {
        let host = newHost()
        serve(host)
        let model = MyShopOrdersModel()
        await model.load(client: client(host))
        #expect(model.phase == .loaded && model.orders.count == 1 && MyShopOrdersModel.canCancel(model.orders[0]))
        let ready = try! JSONDecoder.api.decode(ShopOrder.self, from: Data(orderJSON(status: "bereit").utf8))
        #expect(!MyShopOrdersModel.canCancel(ready))
        let offline = MyShopOrdersModel()
        await offline.load(client: client(newHost()))
        #expect(offline.phase == .failed(text: APIError.network.displayText, isOffline: true))
    }

    @MainActor @Test func cancellingSendsDeleteAndReloads() async {
        let host = newHost()
        serve(host) { (204, "") }
        let api = client(host)
        let model = MyShopOrdersModel()
        await model.load(client: api)
        await model.cancel(model.orders[0], client: api)
        #expect(StubProtocol.requests(host: host).contains { $0.httpMethod == "DELETE" } && model.notice == "Bestellung storniert.")
    }

    @MainActor @Test func aTooLateCancellationShowsTheText() async {
        let host = newHost()
        serve(host) { (409, #"{"code":"STATUS_UNGUELTIG","message":"x"}"#) }
        let api = client(host)
        let model = MyShopOrdersModel()
        await model.load(client: api)
        let order = model.orders[0]
        await model.cancel(order, client: api)
        #expect(model.rowErrors[order.id]?.contains("bereitgestellt") == true && model.busyId == nil)
    }
}
