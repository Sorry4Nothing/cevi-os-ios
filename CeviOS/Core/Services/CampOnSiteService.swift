import Foundation

extension APIClient {
    private func lower(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: Day pages (Tagesseiten)

    /// All camp days by date, each with its page or `nil`. Without blocks, weather and tasks (see `campDayPage`).
    func campDayPages(campId: UUID) async throws -> [CampDayPageEntry] {
        let list: CampDayPageList = try await load("GET", rowPath(campId, "tagesseiten"))
        return list.days
    }

    /// What the day shows: page with day chief, blocks, weather and the tasks due that day (the to-dos of the day).
    func campDayPage(campId: UUID, dayId: UUID) async throws -> CampDayPageDetail {
        try await load("GET", rowPath(campId, "tagesseiten", dayId))
    }

    /// 409 `SEITE_VORHANDEN` if the day has a page.
    func createCampDayPage(campId: UUID, dayId: UUID, _ body: CampDayPageCreate) async throws -> CampDayPage {
        try await load("POST", rowPath(campId, "tagesseiten", dayId), body: body)
    }

    func updateCampDayPage(campId: UUID, dayId: UUID, _ body: CampDayPagePatch) async throws -> CampDayPage {
        try await load("PATCH", rowPath(campId, "tagesseiten", dayId), body: body)
    }

    func createCampDayBlock(campId: UUID, dayId: UUID, _ body: CampDayBlockCreate) async throws -> CampDayBlock {
        try await load("POST", rowPath(campId, "tagesseiten", dayId, "/bloecke"), body: body)
    }

    func updateCampDayBlock(campId: UUID, dayId: UUID, blockId: UUID, _ body: CampDayBlockPatch) async throws -> CampDayBlock {
        try await load("PATCH", rowPath(campId, "tagesseiten", dayId, "/bloecke/" + lower(blockId)), body: body)
    }

    func deleteCampDayBlock(campId: UUID, dayId: UUID, blockId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "tagesseiten", dayId, "/bloecke/" + lower(blockId)), query: versionQuery(version))
    }

    // MARK: Weather (Wetter)

    func campWeather(campId: UUID) async throws -> CampWeather {
        try await load("GET", rowPath(campId, "wetter"))
    }

    /// Camp leadership only. Both values `nil` switch the weather off. Returns the stored place (`nil` if off).
    func setCampWeatherPlace(campId: UUID, latitude: Double?, longitude: Double?) async throws -> CampWeatherPlace? {
        let result: CampWeatherPlaceSetting = try await load("PUT", rowPath(campId, "wetter", nil, "/ort"), body: CampWeatherPlaceSetting(latitude: latitude, longitude: longitude))
        guard let latitude = result.latitude, let longitude = result.longitude else { return nil }
        return CampWeatherPlace(latitude: latitude, longitude: longitude)
    }

    // MARK: Today and my week (Heute, Meine Woche)

    /// 403 if the role reads no part of it.
    func campToday(campId: UUID) async throws -> CampToday {
        try await load("GET", rowPath(campId, "heute"))
    }

    /// 403 if the role reads no part of it.
    func campMyWeek(campId: UUID) async throws -> CampMyWeek {
        try await load("GET", rowPath(campId, "meine-woche"))
    }

    // MARK: Shopping list (Einkauf)

    /// Not for the team (403 by default). `buyer` `.me`: only what the person buys.
    func campShopping(campId: UUID, buyer: CampShoppingBuyerFilter? = nil, done: Bool? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampShoppingPage {
        try await load("GET", rowPath(campId, "einkauf"), query: shoppingQuery(buyer: buyer, done: done, after: after, limit: limit))
    }

    /// Equal items in one row, amounts added.
    func campShoppingTotals(campId: UUID, buyer: CampShoppingBuyerFilter? = nil, done: Bool? = nil, after: UUID? = nil, limit: Int = 100) async throws -> CampShoppingTotalPage {
        try await load("GET", rowPath(campId, "einkauf", nil, "/zusammen"), query: shoppingQuery(buyer: buyer, done: done, after: after, limit: limit))
    }

    /// Names used most in the camp, most used first; `prefix` narrows to names that begin so. One call, at most 50.
    func campShoppingSuggestions(campId: UUID, prefix: String? = nil, limit: Int = 10) async throws -> [CampShoppingSuggestion] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let prefix, !prefix.isEmpty { query.append(URLQueryItem(name: "q", value: prefix)) }
        let list: CampShoppingSuggestionList = try await load("GET", rowPath(campId, "einkauf", nil, "/vorschlaege"), query: query)
        return list.suggestions
    }

    func campShoppingItem(campId: UUID, itemId: UUID) async throws -> CampShoppingItem {
        try await load("GET", rowPath(campId, "einkauf", itemId))
    }

    func createCampShoppingItem(campId: UUID, _ body: CampShoppingCreate) async throws -> CampShoppingItem {
        try await load("POST", rowPath(campId, "einkauf"), body: body)
    }

    /// Changing and ticking off.
    func updateCampShoppingItem(campId: UUID, itemId: UUID, _ body: CampShoppingPatch) async throws -> CampShoppingItem {
        try await load("PATCH", rowPath(campId, "einkauf", itemId), body: body)
    }

    func deleteCampShoppingItem(campId: UUID, itemId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "einkauf", itemId), query: versionQuery(version))
    }

    private func shoppingQuery(buyer: CampShoppingBuyerFilter?, done: Bool?, after: UUID?, limit: Int) -> [URLQueryItem] {
        var query = pageQuery(after: after, limit: limit)
        if let buyer { query.append(URLQueryItem(name: "einkaeufer", value: buyer.queryValue)) }
        if let done { query.append(URLQueryItem(name: "erledigt", value: done ? "true" : "false")) }
        return query
    }

    // MARK: Packing list (Packliste)

    func campPackingList(campId: UUID) async throws -> CampPackingList {
        try await load("GET", rowPath(campId, "packliste"))
    }

    func createCampPackingPoint(campId: UUID, _ body: CampPackingPointCreate) async throws -> CampPackingPoint {
        try await load("POST", rowPath(campId, "packliste", nil, "/punkte"), body: body)
    }

    func updateCampPackingPoint(campId: UUID, pointId: UUID, _ body: CampPackingPointPatch) async throws -> CampPackingPoint {
        try await load("PATCH", rowPath(campId, "packliste", nil, "/punkte/" + lower(pointId)), body: body)
    }

    func deleteCampPackingPoint(campId: UUID, pointId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "packliste", nil, "/punkte/" + lower(pointId)), query: versionQuery(version))
    }

    /// Ticks off, removes or restores a point in the own copy. The same call repeats the same result; no version.
    func setCampPackingState(campId: UUID, pointId: UUID, _ state: CampPackingState) async throws -> CampPackingState {
        let result: CampPackingStateResult = try await load("PUT", rowPath(campId, "packliste", nil, "/punkte/" + lower(pointId) + "/zustand"), body: CampPackingStateBody(state: state))
        return result.state
    }

    /// At most 100 own points per person and camp (409 `LIMIT_ERREICHT`).
    func createOwnCampPackingPoint(campId: UUID, _ body: CampOwnPackingPointCreate) async throws -> CampOwnPackingPoint {
        try await load("POST", rowPath(campId, "packliste", nil, "/eigene"), body: body)
    }

    func updateOwnCampPackingPoint(campId: UUID, pointId: UUID, _ body: CampOwnPackingPointPatch) async throws -> CampOwnPackingPoint {
        try await load("PATCH", rowPath(campId, "packliste", nil, "/eigene/" + lower(pointId)), body: body)
    }

    func deleteOwnCampPackingPoint(campId: UUID, pointId: UUID) async throws {
        try await send("DELETE", rowPath(campId, "packliste", nil, "/eigene/" + lower(pointId)))
    }

    // MARK: Emergency window (Notfall)

    /// Address with map link, contacts with phone and the emergency info sections, in one call. The screen shows the last
    /// loaded answer when there is no network.
    func campEmergency(campId: UUID) async throws -> CampEmergency {
        try await load("GET", rowPath(campId, "notfall"))
    }

    /// Camp leadership only. `nil` removes the link. Returns the stored link.
    func setCampMapLink(campId: UUID, _ link: URL?) async throws -> URL? {
        let result: CampMapLinkResult = try await load("PUT", rowPath(campId, "notfall", nil, "/karte"), body: CampMapLinkBody(mapLink: link))
        return result.mapLink
    }

    func createCampEmergencyContact(campId: UUID, _ body: CampEmergencyContactCreate) async throws -> CampEmergencyContact {
        try await load("POST", rowPath(campId, "notfall", nil, "/kontakte"), body: body)
    }

    func updateCampEmergencyContact(campId: UUID, contactId: UUID, _ body: CampEmergencyContactPatch) async throws -> CampEmergencyContact {
        try await load("PATCH", rowPath(campId, "notfall", nil, "/kontakte/" + lower(contactId)), body: body)
    }

    func deleteCampEmergencyContact(campId: UUID, contactId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "notfall", nil, "/kontakte/" + lower(contactId)), query: versionQuery(version))
    }

    // MARK: Info sections (Infos)

    func campInfos(campId: UUID, after: UUID? = nil, limit: Int = 100) async throws -> CampInfoPage {
        try await load("GET", rowPath(campId, "infos"), query: pageQuery(after: after, limit: limit))
    }

    func campInfo(campId: UUID, infoId: UUID) async throws -> CampInfo {
        try await load("GET", rowPath(campId, "infos", infoId))
    }

    func createCampInfo(campId: UUID, _ body: CampInfoCreate) async throws -> CampInfo {
        try await load("POST", rowPath(campId, "infos"), body: body)
    }

    func updateCampInfo(campId: UUID, infoId: UUID, _ body: CampInfoPatch) async throws -> CampInfo {
        try await load("PATCH", rowPath(campId, "infos", infoId), body: body)
    }

    func deleteCampInfo(campId: UUID, infoId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "infos", infoId), query: versionQuery(version))
    }

    func reorderCampInfos(campId: UUID, _ order: [CampVersionRef]) async throws {
        try await send("PUT", rowPath(campId, "infos", nil, "/reihenfolge"), body: CampOrderBody(entries: order))
    }
}
