import Foundation

/// Files (links), documents, address book and search of a camp. Rows with a `version` answer 409 `VERSION_KONFLIKT`
/// when changed meanwhile: `CampRules.versionConflict`.
extension APIClient {
    // MARK: File links (Dateien)

    /// Stores a link to a file at the storage place. The server never fetches the link and never stores content.
    /// 400 `LINK_UNGUELTIG` or `LINK_HOST_NICHT_ERLAUBT` if the link is refused.
    func createCampFile(campId: UUID, _ body: CampFileCreate) async throws -> CampFileRef {
        try await load("POST", rowPath(campId, "dateien"), body: body)
    }

    func campFile(campId: UUID, fileId: UUID) async throws -> CampFileRef {
        try await load("GET", rowPath(campId, "dateien", fileId))
    }

    /// Removes the link in Cevi OS, never the file at the storage place.
    func deleteCampFile(campId: UUID, fileId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "dateien", fileId), query: versionQuery(version))
    }

    // MARK: Documents

    func campDocuments(campId: UUID, filter: CampDocumentFilter = CampDocumentFilter(), after: UUID? = nil, limit: Int = 50) async throws -> CampDocumentPage {
        try await load("GET", rowPath(campId, "dokumente"), query: pageQuery(after: after, limit: limit) + filter.queryItems)
    }

    func campDocument(campId: UUID, documentId: UUID) async throws -> CampDocument {
        try await load("GET", rowPath(campId, "dokumente", documentId))
    }

    func createCampDocument(campId: UUID, _ body: CampDocumentCreate) async throws -> CampDocument {
        try await load("POST", rowPath(campId, "dokumente"), body: body)
    }

    func updateCampDocument(campId: UUID, documentId: UUID, _ body: CampDocumentPatch) async throws -> CampDocument {
        try await load("PATCH", rowPath(campId, "dokumente", documentId), body: body)
    }

    /// Soft delete: the row stays in the trash of the server, the file at the storage place stays.
    func deleteCampDocument(campId: UUID, documentId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "dokumente", documentId), query: versionQuery(version))
    }

    // MARK: Address book (Adressbuch, camp leadership only)

    /// `search` looks in name, function and group (1 to 100 characters).
    func campContacts(campId: UUID, search: String? = nil, after: UUID? = nil, limit: Int = 50) async throws -> CampContactPage {
        var query = pageQuery(after: after, limit: limit)
        if let search { query.append(URLQueryItem(name: "q", value: search)) }
        return try await load("GET", rowPath(campId, "adressbuch"), query: query)
    }

    func campContact(campId: UUID, contactId: UUID) async throws -> CampContact {
        try await load("GET", rowPath(campId, "adressbuch", contactId))
    }

    func createCampContact(campId: UUID, _ body: CampContactCreate) async throws -> CampContact {
        try await load("POST", rowPath(campId, "adressbuch"), body: body)
    }

    func updateCampContact(campId: UUID, contactId: UUID, _ body: CampContactPatch) async throws -> CampContact {
        try await load("PATCH", rowPath(campId, "adressbuch", contactId), body: body)
    }

    func deleteCampContact(campId: UUID, contactId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "adressbuch", contactId), query: versionQuery(version))
    }

    // MARK: Search

    /// Full text search over everything the role may see. `text` has 2 to 100 characters; the server tolerates typos.
    func searchCamp(campId: UUID, text: String, type: CampSearchType? = nil) async throws -> CampSearchResult {
        var query = [URLQueryItem(name: "q", value: text)]
        if let type { query.append(URLQueryItem(name: "typ", value: type.rawValue)) }
        return try await load("GET", campPath(campId) + "/suche", query: query)
    }
}
