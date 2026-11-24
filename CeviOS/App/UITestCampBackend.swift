#if DEBUG
import Foundation

/// The mutable part of the simulated camp server: what the UI tests change (task status, checklist ticks, new notices).
/// Everything else is served unchanged from `UITestCampFixtures`.
nonisolated struct UITestCampState: @unchecked Sendable {
    var tasks: [[String: Any]]
    var checklist: [[String: Any]]
    var notices: [[String: Any]]
    /// The first status change of the task «Busfahrt buchen» meets a concurrent edit (409 `VERSION_KONFLIKT`).
    var conflictPending = true
    var counter = 0x4000

    static let conflictTask = "0190a000-0000-7000-8000-000000000205"

    init() {
        tasks = Self.fixture("/aufgaben")["aufgaben"] as? [[String: Any]] ?? []
        checklist = Self.fixture("/aufgaben/{}/details")["checkliste"] as? [[String: Any]] ?? []
        notices = Self.fixture("/pinnwand")["beitraege"] as? [[String: Any]] ?? []
    }

    static func fixture(_ route: String) -> [String: Any] {
        (UITestCampFixtures.routes[route]).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
    }
}

nonisolated extension World {
    static let activeCamp = "0190a000-0000-7000-8000-000000000001"
    static let closedCamp = "0190a000-0000-7000-8000-000000000002"

    /// Role in the camps: `leitung…` camp lead, `team…` team, everyone else is not a member.
    private func campRole(_ me: Person) -> String? {
        if me.username.hasPrefix("team") { return "team" }
        return me.username.hasPrefix("leitung") ? "lagerleitung" : nil
    }

    private func campObject(_ id: String, role: String) -> [String: Any] {
        let closed = id == Self.closedCamp
        return [
            "id": id, "titel": closed ? "Herbstlager Beispiel 2026" : "Sommerlager Beispiel 2027",
            "von": closed ? "{{D-60}}" : "{{D+12}}", "bis": closed ? "{{D-53}}" : "{{D+19}}", "vorbereitungAb": NSNull(),
            "ort": "Beispielwald", "adresse": "Beispielweg 1, 8000 Beispielstadt", "status": closed ? "abgeschlossen" : "aktiv",
            "farbe": "#003973", "logoMediumId": NSNull(), "rolle": role,
        ]
    }

    /// Camp reply: the JSON gets its date tokens resolved.
    private func campReply(_ status: Int, _ object: Any) -> Reply {
        guard let data = try? JSONSerialization.data(withJSONObject: object), var text = String(data: data, encoding: .utf8) else { return .notFound }
        text = Self.resolveTokens(text)
        return Reply(status: status, body: Data(text.utf8))
    }

    private static func resolveTokens(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\{\{([DT])([+-]\d+)\}\}"#) else { return text }
        var result = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let kind = Range(match.range(at: 1), in: text),
                  let days = Range(match.range(at: 2), in: text).flatMap({ Int(text[$0]) }) else { continue }
            let replacement = text[kind] == "D"
                ? DateFormats.calendarDayText(date(days: days, hour: 2))
                : DateFormats.timestampText(date(days: days, hour: 9))
            result.replaceSubrange(whole, with: replacement)
        }
        return result
    }

    private func fixture(_ route: String) -> Reply {
        guard let json = UITestCampFixtures.routes[route] else { return .notFound }
        return Reply(status: 200, body: Data(Self.resolveTokens(json).utf8))
    }

    private func forbidden() -> Reply { .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.") }

    mutating func campSettings(_ request: Request, _ me: Person) -> Reply {
        request.method == "GET" ? fixture("/ich/lager-benachrichtigungen") : .noContent
    }

    mutating func campRoutes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        guard let role = campRole(me) else {
            return request.method == "GET" && route.isEmpty ? campReply(200, ["lager": [Any]()]) : .notFound
        }
        guard let id = route.first else {
            return campReply(200, ["lager": [Self.activeCamp, Self.closedCamp].map { campObject($0, role: role) }])
        }
        guard id == Self.activeCamp || id == Self.closedCamp else { return .notFound }
        let ids = route.dropFirst().filter { $0.count == 36 }
        let area = route.dropFirst().map { $0.count == 36 ? "{}" : $0 }.joined(separator: "/")
        if area.isEmpty {
            var object = campObject(id, role: role)
            object["schreibgeschuetzt"] = id == Self.closedCamp
            return campReply(200, object)
        }
        if request.method != "GET", id == Self.closedCamp {
            return .error(409, "LAGER_GESCHLOSSEN", "Das Lager ist abgeschlossen.")
        }
        return request.method == "GET" ? read(area, ids, request, role) : write(request, area, ids, role)
    }

    // MARK: Reading

    private func read(_ area: String, _ ids: [String], _ request: Request, _ role: String) -> Reply {
        // The team has no task list, no portfolios and no inbox (the schedule is readable for every role).
        if role == "team", ["rechte", "aufgaben", "ressorts", "eingang"].contains(area) { return forbidden() }
        switch area {
        case "aufgaben":
            return campReply(200, ["aufgaben": campState.tasks, "naechster": NSNull()])
        case "aufgaben/{}":
            guard let task = campState.tasks.first(where: { $0["id"] as? String == ids[0] }) else { return .notFound }
            return campReply(200, task)
        case "aufgaben/{}/details":
            var details = UITestCampState.fixture("/aufgaben/{}/details")
            details["aufgabeId"] = ids[0]
            details["checkliste"] = campState.checklist.map { $0.merging(["aufgabeId": ids[0]]) { _, new in new } }
            return campReply(200, details)
        case "pinnwand":
            return campReply(200, ["beitraege": campState.notices, "naechster": NSNull()])
        case "pinnwand/{}":
            guard let notice = campState.notices.first(where: { $0["id"] as? String == ids[0] }) else { return .notFound }
            return campReply(200, notice)
        case "start":
            return role == "team" ? teamStart() : fixtureStart()
        default:
            return fixture("/" + area)
        }
    }


    /// The start page follows the tasks as they stand now.
    private func fixtureStart() -> Reply {
        var start = UITestCampState.fixture("/start")
        let tasks = campState.tasks
        let open = tasks.filter { $0["status"] as? String != "erledigt" }
        start["eigene"] = open
        start["ueberfaellig"] = open.filter { ($0["frist"] as? String)?.hasPrefix("{{D-") == true }
        start["fortschritt"] = [
            "aufgaben": ["gesamt": tasks.count, "erledigt": tasks.count - open.count, "ueberfaellig": (start["ueberfaellig"] as? [Any])?.count ?? 0],
            "meilensteine": (start["fortschritt"] as? [String: Any])?["meilensteine"] ?? NSNull(),
        ] as [String: Any]
        return campReply(200, start)
    }

    /// The team may not read the tasks: no numbers, no lists.
    private func teamStart() -> Reply {
        var start = UITestCampState.fixture("/start")
        start["eigene"] = NSNull()
        start["ueberfaellig"] = NSNull()
        start["fortschritt"] = ["aufgaben": NSNull(), "meilensteine": NSNull()] as [String: Any]
        return campReply(200, start)
    }

    // MARK: Writing

    private mutating func write(_ request: Request, _ area: String, _ ids: [String], _ role: String) -> Reply {
        switch (request.method, area) {
        case ("PUT", "aufgaben/{}/status"):
            return setStatus(ids[0], request.body)
        case ("PATCH", "aufgaben/{}/checkliste/{}"):
            guard let index = campState.checklist.firstIndex(where: { $0["id"] as? String == ids[1] }) else { return .notFound }
            var item = campState.checklist[index]
            if let done = request.body["erledigt"] as? Bool { item["erledigt"] = done }
            if let text = request.body["text"] as? String { item["text"] = text }
            item["version"] = (item["version"] as? Int ?? 1) + 1
            campState.checklist[index] = item
            return campReply(200, item)
        case ("POST", "pinnwand"):
            campState.counter += 1
            var notice = campState.notices.last ?? [:]
            notice["id"] = String(format: "0190a000-0000-7000-8000-%012x", campState.counter)
            notice["version"] = 1
            notice["titel"] = request.body["titel"] as? String ?? "Neuer Beitrag"
            notice["text"] = request.body["text"] as? String ?? ""
            notice["wichtig"] = request.body["wichtig"] as? Bool ?? false
            notice["angeheftet"] = false
            notice["umfrage"] = NSNull()
            notice["dateien"] = [Any]()
            notice["erstelltAm"] = "{{T+0}}"
            campState.notices.insert(notice, at: 0)
            return campReply(201, notice)
        default:
            return .noContent
        }
    }

    private mutating func setStatus(_ id: String, _ body: [String: Any]) -> Reply {
        guard let index = campState.tasks.firstIndex(where: { $0["id"] as? String == id }) else { return .notFound }
        var task = campState.tasks[index]
        let version = task["version"] as? Int ?? 1
        if id == UITestCampState.conflictTask, campState.conflictPending {
            campState.conflictPending = false
            task["version"] = version + 1
            task["status"] = "laeuft"
            task["notiz"] = "Jan hat den Bus schon angefragt."
            campState.tasks[index] = task
            return conflict(task, differing: ["status", "notiz"])
        }
        if let sent = body["version"] as? Int, sent != version { return conflict(task, differing: ["status"]) }
        let status = body["status"] as? String ?? "offen"
        task["status"] = status
        task["version"] = version + 1
        task["erledigtAm"] = status == "erledigt" ? "{{T+0}}" : NSNull()
        campState.tasks[index] = task
        return campReply(200, task)
    }

    private func conflict(_ current: [String: Any], differing: [String]) -> Reply {
        campReply(409, ["code": "VERSION_KONFLIKT", "message": "Jemand hat diese Aufgabe gerade geändert.", "aktuell": current, "abweichend": differing])
    }
}
#endif
