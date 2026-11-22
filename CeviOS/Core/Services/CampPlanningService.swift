import Foundation

/// Writing routes carry the `version` the app last saw. If the row changed since, the server answers 409
/// `VERSION_KONFLIKT`: read it with `CampRules.versionConflict`.
extension APIClient {
    private func rowPath(_ campId: UUID, _ area: String, _ id: UUID? = nil, _ rest: String = "") -> String {
        var path = campPath(campId) + "/" + area
        if let id { path += "/" + id.uuidString.lowercased() }
        return path + rest
    }

    private func pageQuery(after: UUID?, limit: Int) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { query.append(URLQueryItem(name: "nach", value: after.uuidString.lowercased())) }
        return query
    }

    private func versionQuery(_ version: Int) -> [URLQueryItem] { [URLQueryItem(name: "version", value: String(version))] }

    // MARK: Portfolios (Ressorts)

    /// Flat list; the app builds the tree from `parentId`. `after` is the cursor `next` of the previous page.
    func campPortfolios(campId: UUID, after: UUID? = nil, limit: Int = 100) async throws -> CampPortfolioPage {
        try await load("GET", rowPath(campId, "ressorts"), query: pageQuery(after: after, limit: limit))
    }

    func campPortfolio(campId: UUID, portfolioId: UUID) async throws -> CampPortfolio {
        try await load("GET", rowPath(campId, "ressorts", portfolioId))
    }

    func createCampPortfolio(campId: UUID, _ body: CampPortfolioCreate) async throws -> CampPortfolio {
        try await load("POST", rowPath(campId, "ressorts"), body: body)
    }

    func updateCampPortfolio(campId: UUID, portfolioId: UUID, _ body: CampPortfolioPatch) async throws -> CampPortfolio {
        try await load("PATCH", rowPath(campId, "ressorts", portfolioId), body: body)
    }

    /// 409 `RESSORT_HAT_UNTERRESSORTS` if it still has sub-portfolios.
    func deleteCampPortfolio(campId: UUID, portfolioId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "ressorts", portfolioId), query: versionQuery(version))
    }

    func reorderCampPortfolios(campId: UUID, _ entries: [CampVersionRef]) async throws {
        try await send("PUT", rowPath(campId, "ressorts", nil, "/reihenfolge"), body: CampOrderBody(entries: entries))
    }

    func campPortfolioLinks(campId: UUID, portfolioId: UUID, after: UUID? = nil, limit: Int = 100) async throws -> CampPortfolioLinkPage {
        try await load("GET", rowPath(campId, "ressorts", portfolioId, "/links"), query: pageQuery(after: after, limit: limit))
    }

    func createCampPortfolioLink(campId: UUID, portfolioId: UUID, _ body: CampLinkCreate) async throws -> CampPortfolioLink {
        try await load("POST", rowPath(campId, "ressorts", portfolioId, "/links"), body: body)
    }

    func updateCampPortfolioLink(campId: UUID, portfolioId: UUID, linkId: UUID, _ body: CampLinkPatch) async throws -> CampPortfolioLink {
        try await load("PATCH", rowPath(campId, "ressorts", portfolioId, "/links/" + linkId.uuidString.lowercased()), body: body)
    }

    func deleteCampPortfolioLink(campId: UUID, portfolioId: UUID, linkId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "ressorts", portfolioId, "/links/" + linkId.uuidString.lowercased()), query: versionQuery(version))
    }

    /// Newest first.
    func campPortfolioNotes(campId: UUID, portfolioId: UUID, after: UUID? = nil, limit: Int = 50) async throws -> CampPortfolioNotePage {
        try await load("GET", rowPath(campId, "ressorts", portfolioId, "/notizen"), query: pageQuery(after: after, limit: limit))
    }

    func createCampPortfolioNote(campId: UUID, portfolioId: UUID, text: String) async throws -> CampPortfolioNote {
        try await load("POST", rowPath(campId, "ressorts", portfolioId, "/notizen"), body: CampTextBody(text: text))
    }

    func updateCampPortfolioNote(campId: UUID, portfolioId: UUID, noteId: UUID, version: Int, text: String) async throws -> CampPortfolioNote {
        try await load("PATCH", rowPath(campId, "ressorts", portfolioId, "/notizen/" + noteId.uuidString.lowercased()), body: CampNotePatch(version: version, text: text))
    }

    func deleteCampPortfolioNote(campId: UUID, portfolioId: UUID, noteId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "ressorts", portfolioId, "/notizen/" + noteId.uuidString.lowercased()), query: versionQuery(version))
    }

    // MARK: Tasks (Aufgaben)

    /// Sorted by `order`. The team gets only its own tasks.
    func campTasks(campId: UUID, filter: CampTaskFilter = CampTaskFilter(), after: UUID? = nil, limit: Int = 100) async throws -> CampTaskPage {
        try await load("GET", rowPath(campId, "aufgaben"), query: pageQuery(after: after, limit: limit) + filter.queryItems)
    }

    func campTask(campId: UUID, taskId: UUID) async throws -> CampTask {
        try await load("GET", rowPath(campId, "aufgaben", taskId))
    }

    func createCampTask(campId: UUID, _ body: CampTaskCreate) async throws -> CampTask {
        try await load("POST", rowPath(campId, "aufgaben"), body: body)
    }

    func updateCampTask(campId: UUID, taskId: UUID, _ body: CampTaskPatch) async throws -> CampTask {
        try await load("PATCH", rowPath(campId, "aufgaben", taskId), body: body)
    }

    func deleteCampTask(campId: UUID, taskId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "aufgaben", taskId), query: versionQuery(version))
    }

    func reorderCampTasks(campId: UUID, _ entries: [CampVersionRef]) async throws {
        try await send("PUT", rowPath(campId, "aufgaben", nil, "/reihenfolge"), body: CampOrderBody(entries: entries))
    }

    /// The only change the team may make on its own tasks.
    func setCampTaskStatus(campId: UUID, taskId: UUID, version: Int, status: CampTaskStatus) async throws -> CampTask {
        try await load("PUT", rowPath(campId, "aufgaben", taskId, "/status"), body: CampTaskStatusBody(version: version, status: status))
    }

    /// Open tasks with the same title in the same portfolio. With `title`: the tasks that already carry this title.
    func campTaskDuplicates(campId: UUID, title: String? = nil, portfolioId: UUID? = nil) async throws -> CampTaskDuplicates {
        var query: [URLQueryItem] = []
        if let title { query.append(URLQueryItem(name: "titel", value: title)) }
        if let portfolioId { query.append(URLQueryItem(name: "ressortId", value: portfolioId.uuidString.lowercased())) }
        return try await load("GET", rowPath(campId, "aufgaben", nil, "/duplikate"), query: query)
    }

    func campTaskDetails(campId: UUID, taskId: UUID) async throws -> CampTaskDetails {
        try await load("GET", rowPath(campId, "aufgaben", taskId, "/details"))
    }

    /// Newest first; `before` is the cursor `next` of the previous page.
    func campTaskHistory(campId: UUID, taskId: UUID, before: Int? = nil, limit: Int = 50) async throws -> CampTaskHistory {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before { query.append(URLQueryItem(name: "vor", value: String(before))) }
        return try await load("GET", rowPath(campId, "aufgaben", taskId, "/verlauf"), query: query)
    }

    func createCampChecklistItem(campId: UUID, taskId: UUID, _ body: CampChecklistCreate) async throws -> CampChecklistItem {
        try await load("POST", rowPath(campId, "aufgaben", taskId, "/checkliste"), body: body)
    }

    /// Edit the text or tick the item.
    func updateCampChecklistItem(campId: UUID, taskId: UUID, itemId: UUID, _ body: CampChecklistPatch) async throws -> CampChecklistItem {
        try await load("PATCH", rowPath(campId, "aufgaben", taskId, "/checkliste/" + itemId.uuidString.lowercased()), body: body)
    }

    func deleteCampChecklistItem(campId: UUID, taskId: UUID, itemId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "aufgaben", taskId, "/checkliste/" + itemId.uuidString.lowercased()), query: versionQuery(version))
    }

    func reorderCampChecklist(campId: UUID, taskId: UUID, _ entries: [CampVersionRef]) async throws {
        try await send("PUT", rowPath(campId, "aufgaben", taskId, "/checkliste/reihenfolge"), body: CampOrderBody(entries: entries))
    }

    func createCampTaskLink(campId: UUID, taskId: UUID, _ body: CampLinkCreate) async throws -> CampTaskLink {
        try await load("POST", rowPath(campId, "aufgaben", taskId, "/links"), body: body)
    }

    func updateCampTaskLink(campId: UUID, taskId: UUID, linkId: UUID, _ body: CampLinkPatch) async throws -> CampTaskLink {
        try await load("PATCH", rowPath(campId, "aufgaben", taskId, "/links/" + linkId.uuidString.lowercased()), body: body)
    }

    func deleteCampTaskLink(campId: UUID, taskId: UUID, linkId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "aufgaben", taskId, "/links/" + linkId.uuidString.lowercased()), query: versionQuery(version))
    }

    /// Replaces all keywords of the task (`version` is the version of the task).
    func setCampTaskKeywords(campId: UUID, taskId: UUID, version: Int, keywords: [String]) async throws -> CampTaskDetails {
        try await load("PUT", rowPath(campId, "aufgaben", taskId, "/stichworte"), body: CampKeywordsBody(version: version, keywords: keywords))
    }

    /// The task absorbs `withId`; the other one goes to the recycle bin. Both versions are checked.
    func mergeCampTasks(campId: UUID, taskId: UUID, version: Int, withId: UUID, withVersion: Int) async throws -> CampTask {
        let body = CampTaskMergeBody(version: version, withId: withId, withVersion: withVersion)
        return try await load("POST", rowPath(campId, "aufgaben", taskId, "/zusammenfuehren"), body: body)
    }

    /// Quick entry, step 1: one suggestion per line, nothing is saved. Step 2 is `createCampTask` with
    /// `CampTaskCreate(confirming:)` for each line the person confirms.
    func suggestCampTasks(campId: UUID, text: String) async throws -> [CampTaskSuggestion] {
        let result: CampTaskSuggestions = try await load("POST", rowPath(campId, "aufgaben", nil, "/schnell"), body: CampQuickEntryBody(text: text))
        return result.suggestions
    }

    // MARK: Schedule (Zeitplan)

    func campSchedule(campId: UUID) async throws -> CampSchedule {
        try await load("GET", rowPath(campId, "zeitplan"))
    }

    /// Camp days and day sections the server proposes. Nothing is saved until `adoptCampSchedule`.
    func campScheduleProposal(campId: UUID) async throws -> CampScheduleProposal {
        try await load("GET", rowPath(campId, "zeitplan", nil, "/vorschlag"))
    }

    func adoptCampSchedule(campId: UUID, _ body: CampScheduleAdopt) async throws -> CampScheduleAdopted {
        try await load("POST", rowPath(campId, "zeitplan", nil, "/uebernehmen"), body: body)
    }

    func createCampMilestone(campId: UUID, _ body: CampMilestoneCreate) async throws -> CampMilestone {
        try await load("POST", rowPath(campId, "zeitplan", nil, "/meilensteine"), body: body)
    }

    func updateCampMilestone(campId: UUID, milestoneId: UUID, _ body: CampMilestonePatch) async throws -> CampMilestone {
        try await load("PATCH", rowPath(campId, "zeitplan", nil, "/meilensteine/" + milestoneId.uuidString.lowercased()), body: body)
    }

    func deleteCampMilestone(campId: UUID, milestoneId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "zeitplan", nil, "/meilensteine/" + milestoneId.uuidString.lowercased()), query: versionQuery(version))
    }

    /// Moving a milestone, step 1: preview of the new date and the deadlines that move along. Nothing is written.
    func previewCampMilestoneMove(campId: UUID, milestoneId: UUID, version: Int, to date: Date) async throws -> CampMilestoneMove {
        let body = CampMilestoneMoveBody(dryRun: true, date: CampCalendarDay(date), version: version)
        return try await load("POST", rowPath(campId, "zeitplan", nil, "/meilensteine/" + milestoneId.uuidString.lowercased() + "/verschieben"), body: body)
    }

    /// Step 2: confirm with the milestone version and the tasks (`CampMilestoneMove.taskRefs`) of the preview.
    /// If the set or a version changed meanwhile the server writes nothing and answers 409 (`VORSCHAU_VERALTET`).
    func confirmCampMilestoneMove(campId: UUID, milestoneId: UUID, version: Int, to date: Date, tasks: [CampVersionRef]) async throws -> CampMilestoneMove {
        let body = CampMilestoneMoveBody(dryRun: false, date: CampCalendarDay(date), version: version, tasks: tasks)
        return try await load("POST", rowPath(campId, "zeitplan", nil, "/meilensteine/" + milestoneId.uuidString.lowercased() + "/verschieben"), body: body)
    }

    func createCampDay(campId: UUID, _ body: CampDayCreate) async throws -> CampDay {
        try await load("POST", rowPath(campId, "zeitplan", nil, "/lagertage"), body: body)
    }

    func updateCampDay(campId: UUID, dayId: UUID, _ body: CampDayPatch) async throws -> CampDay {
        try await load("PATCH", rowPath(campId, "zeitplan", nil, "/lagertage/" + dayId.uuidString.lowercased()), body: body)
    }

    func deleteCampDay(campId: UUID, dayId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "zeitplan", nil, "/lagertage/" + dayId.uuidString.lowercased()), query: versionQuery(version))
    }

    func createCampDaySection(campId: UUID, _ body: CampSectionCreate) async throws -> CampDaySection {
        try await load("POST", rowPath(campId, "zeitplan", nil, "/tagesabschnitte"), body: body)
    }

    func updateCampDaySection(campId: UUID, sectionId: UUID, _ body: CampSectionPatch) async throws -> CampDaySection {
        try await load("PATCH", rowPath(campId, "zeitplan", nil, "/tagesabschnitte/" + sectionId.uuidString.lowercased()), body: body)
    }

    func deleteCampDaySection(campId: UUID, sectionId: UUID, version: Int) async throws {
        try await send("DELETE", rowPath(campId, "zeitplan", nil, "/tagesabschnitte/" + sectionId.uuidString.lowercased()), query: versionQuery(version))
    }

    // MARK: Private to-dos

    func campTodos(campId: UUID) async throws -> [CampTodo] {
        let list: CampTodoList = try await load("GET", rowPath(campId, "todos"))
        return list.todos
    }

    func createCampTodo(campId: UUID, _ body: CampTodoCreate) async throws -> CampTodo {
        try await load("POST", rowPath(campId, "todos"), body: body)
    }

    func updateCampTodo(campId: UUID, todoId: UUID, _ body: CampTodoPatch) async throws -> CampTodo {
        try await load("PATCH", rowPath(campId, "todos", todoId), body: body)
    }

    func deleteCampTodo(campId: UUID, todoId: UUID) async throws {
        try await send("DELETE", rowPath(campId, "todos", todoId))
    }

    // MARK: Templates, start, decisions

    /// With `dryRun` the answer lists what would be created and nothing is written.
    func applyCampTemplate(campId: UUID, templateId: UUID, dryRun: Bool = false) async throws -> CampTemplateApplication {
        let query = dryRun ? [URLQueryItem(name: "trocken", value: "true")] : []
        return try await load("POST", rowPath(campId, "vorlagen", templateId, "/anwenden"), query: query)
    }

    /// Start page of the camp lead: countdown, progress, overdue tasks.
    func campStart(campId: UUID) async throws -> CampStart {
        try await load("GET", rowPath(campId, "start"))
    }

    func campDecisions(campId: UUID, after: UUID? = nil, limit: Int = 50) async throws -> CampDecisionPage {
        try await load("GET", rowPath(campId, "entscheide"), query: pageQuery(after: after, limit: limit))
    }
}
