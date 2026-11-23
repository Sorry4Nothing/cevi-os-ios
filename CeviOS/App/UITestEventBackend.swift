#if DEBUG
import Foundation

/// The mutable part of the simulated server for «Mein Kalender», suggestions, rooms and the occasion registration.
nonisolated struct UITestEventState: @unchecked Sendable {
    var linkActive = false
    var linkCounter = 0
    var suggestions: [[String: Any]] = []
    var requests: [[String: Any]] = []
    /// Registrations by participant (child id or the person's id).
    var registrations: [String: [String: Any]] = [:]
    var counter = 0x7000
    /// A title of this text meets a server error once, so the UI tests reach «Fehler beim Speichern».
    var failureTitle = "Serverfehler"
    var failurePending = true
}

nonisolated extension World {
    static let camp2027 = "00000000-0000-0000-0000-0000000000a5"
    static let occasion = "00000000-0000-0000-0000-0000000000d1"
    static let roomMain = "00000000-0000-0000-0000-0000000000e1"
    static let roomBooked = "00000000-0000-0000-0000-0000000000e2"
    static let tagTeam = "00000000-0000-0000-0000-0000000000f1"

    private mutating func nextId() -> String {
        eventState.counter += 1
        return String(format: "00000000-0000-0000-0000-%012x", eventState.counter)
    }

    // MARK: Routes

    mutating func eventRoutes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        switch (request.method, route.first) {
        case ("GET", "termine"): return calendar(route.dropFirst().first, me)
        case (_, "ich"): return calendarLink(request)
        case (_, "termin-vorschlaege"): return suggestionRoutes(request, Array(route.dropFirst()), me)
        case (_, "raeume"): return roomRoutes(request, Array(route.dropFirst()), me)
        case (_, "anlaesse"): return occasionRoutes(request, Array(route.dropFirst()), me)
        default: return .notFound
        }
    }

    // MARK: Mein Kalender

    private func tags(_ p: Program) -> [[String: Any]] {
        p.units.map { ["id": $0, "name": Self.unitNames[$0]?.0 ?? "", "typ": "stufe"] }
    }

    /// Events as the list sends them: the person's children only, the occasion on the camp.
    private func event(_ p: Program, for me: Person) -> [String: Any] {
        var object = program(p, for: me)
        for key in ["stufen", "sichtbarkeit", "treffpunkt", "schlussOrt", "schlussZeit", "mitnehmen", "teilnahmeOffen", "eigeneAnmeldung"] {
            object[key] = nil
        }
        object["ort"] = orNull(p.meetingPoint ?? "Beispielwald")
        object["tags"] = tags(p)
        object["anlass"] = p.id == Self.camp2027
            ? ["id": Self.occasion, "anmeldeschluss": DateFormats.timestampText(Self.date(days: 30, hour: 12)), "anmeldungOffen": true,
               "angemeldet": !eventState.registrations.isEmpty] as [String: Any]
            : NSNull()
        return object
    }

    private func calendar(_ id: String?, _ me: Person) -> Reply {
        let mine = programs.filter { isVisible($0, to: me) && $0.visibility != "intern" }
        guard let id, id != "mein" else {
            let visible = mine.filter { $0.day + $0.length > 0 }.sorted { $0.start < $1.start }
            return .json(200, ["termine": visible.map { event($0, for: me) }, "weitere": false, "naechste": NSNull()])
        }
        guard let p = mine.first(where: { $0.id == id }) else { return .notFound }
        var object = event(p, for: me)
        let full = program(p, for: me)
        for key in ["treffpunkt", "schlussOrt", "schlussZeit", "mitnehmen", "teilnahmeOffen", "eigeneAnmeldung"] { object[key] = full[key] }
        return .json(200, object)
    }

    // MARK: Calendar link

    private mutating func calendarLink(_ request: Request) -> Reply {
        switch request.method {
        case "GET":
            var object: [String: Any] = ["aktiv": eventState.linkActive]
            object["erstelltAm"] = eventState.linkActive ? DateFormats.timestampText(.now) : NSNull()
            object["zuletztAbgerufenAm"] = NSNull()
            object["endung"] = eventState.linkActive ? String(format: "t%03d", eventState.linkCounter) : NSNull()
            return .json(200, object)
        case "POST":
            eventState.linkActive = true
            eventState.linkCounter += 1
            let suffix = String(format: "t%03d", eventState.linkCounter)
            // Not a real token: the UI tests must never hold a usable secret.
            return .json(201, ["token": "ui-test-token-\(suffix)", "pfad": "/ical/ui-test-token-\(suffix).ics",
                               "erstelltAm": DateFormats.timestampText(.now), "endung": suffix])
        case "DELETE":
            eventState.linkActive = false
            return .noContent
        default:
            return .notFound
        }
    }

    // MARK: Suggestions

    private mutating func suggestionRoutes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        switch (request.method, route.first) {
        case ("GET", "optionen"):
            let options = Self.unitNames.keys.sorted().map { ["id": $0, "name": Self.unitNames[$0]?.0 ?? "", "typ": "stufe"] as [String: Any] }
                + [["id": Self.tagTeam, "name": "Team Mat", "typ": "team"] as [String: Any]]
            return .json(200, ["darfVorschlagen": me.kind == .leader, "tags": options])
        case ("GET", "meine"):
            return .json(200, ["vorschlaege": eventState.suggestions, "weitere": false, "naechste": NSNull()])
        case ("POST", nil):
            guard me.kind == .leader else { return .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.") }
            let title = (request.body["titel"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let tagIds = request.body["tagIds"] as? [String] ?? []
            guard !title.isEmpty, !tagIds.isEmpty else { return .error(400, "UNGUELTIG", "Die Eingabe ist ungültig.") }
            if title == eventState.failureTitle, eventState.failurePending {
                eventState.failurePending = false
                return .json(500, [String: String]())
            }
            let id = nextId()
            eventState.suggestions.append([
                "id": id, "status": "offen", "titel": title, "ganztaegig": false, "beginn": request.body["beginn"] ?? NSNull(),
                "ende": request.body["ende"] ?? NSNull(), "tagVon": NSNull(), "tagBis": NSNull(), "ort": orNull(request.body["ort"]),
                "beschreibung": orNull(request.body["beschreibung"]), "bemerkung": NSNull(), "tags": [], "begruendung": NSNull(),
                "entschiedenAm": NSNull(), "erstelltAm": DateFormats.timestampText(.now), "vorgeschlagenVon": me.id,
            ])
            return .json(201, ["id": id, "status": "offen"])
        case ("DELETE", let id?):
            eventState.suggestions.removeAll { $0["id"] as? String == id }
            return .noContent
        default:
            return .notFound
        }
    }

    // MARK: Rooms

    private func rooms() -> [[String: Any]] {
        [
            ["id": Self.roomMain, "name": "Pfadiheim Beispielwald", "ort": "Beispielwald", "beschreibung": "Saal und Küche",
             "kapazitaet": 40, "aktiv": true, "team": ["id": Self.tagTeam, "name": "Team Mat"]],
            ["id": Self.roomBooked, "name": "Gruppenraum Keller", "ort": "Beispielstadt", "beschreibung": NSNull(),
             "kapazitaet": 12, "aktiv": true, "team": NSNull()],
        ]
    }

    private func roomRequest(_ id: String, room: String, name: String, start: Date, end: Date, purpose: String, status: String) -> [String: Any] {
        ["id": id, "raumId": room, "raumName": name, "beginn": DateFormats.timestampText(start), "ende": DateFormats.timestampText(end),
         "zweck": purpose, "status": status, "begruendung": NSNull(), "entschiedenAm": NSNull(),
         "erstelltAm": DateFormats.timestampText(.now), "vonName": NSNull()]
    }

    private mutating func roomRoutes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        if injectedEmptyRooms, request.method == "GET", route.isEmpty { return .json(200, ["raeume": [Any](), "weitere": false, "naechste": NSNull()]) }
        switch (request.method, route.first, route.dropFirst().first) {
        case ("GET", nil, _):
            return .json(200, ["raeume": rooms(), "weitere": false, "naechste": NSNull()])
        case ("GET", "anfragen", "meine"):
            let confirmed = roomRequest("00000000-0000-0000-0000-0000000000e3", room: Self.roomBooked, name: "Gruppenraum Keller",
                                        start: Self.date(days: 1, hour: 16), end: Self.date(days: 1, hour: 18), purpose: "Material sortieren", status: "bestaetigt")
            let declined = roomRequest("00000000-0000-0000-0000-0000000000e4", room: Self.roomMain, name: "Pfadiheim Beispielwald",
                                       start: Self.date(days: 9, hour: 19), end: Self.date(days: 9, hour: 22), purpose: "Leitungshöck", status: "abgelehnt")
            return .json(200, ["anfragen": eventState.requests + [confirmed, declined], "weitere": false, "naechste": NSNull()])
        case ("POST", let room?, "anfragen") where rooms().contains { $0["id"] as? String == room }:
            let name = rooms().first { $0["id"] as? String == room }?["name"] as? String ?? ""
            guard let start = (request.body["beginn"] as? String).flatMap(DateFormats.timestamp),
                  let end = (request.body["ende"] as? String).flatMap(DateFormats.timestamp), end > start,
                  let purpose = request.body["zweck"] as? String, !purpose.trimmingCharacters(in: .whitespaces).isEmpty
            else { return .error(400, "UNGUELTIG", "Die Eingabe ist ungültig.") }
            // The «Gruppenraum Keller» is booked tomorrow from 16:00 to 18:00.
            if room == Self.roomBooked, start < Self.date(days: 1, hour: 18), end > Self.date(days: 1, hour: 16) {
                return .error(409, "RAUM_BELEGT", "Der Raum ist zu dieser Zeit schon bestätigt vergeben.")
            }
            let id = nextId()
            eventState.requests.append(roomRequest(id, room: room, name: name, start: start, end: end, purpose: purpose, status: "angefragt"))
            return .json(201, ["id": id, "status": "angefragt"])
        case ("DELETE", "anfragen", let id?):
            eventState.requests.removeAll { $0["id"] as? String == id }
            return .noContent
        default:
            return .notFound
        }
    }

    private var injectedEmptyRooms: Bool { failure == "noRooms" }

    // MARK: Occasion registration

    private static var occasionFields: [[String: Any]] { [
        ["schluessel": "schwimmt", "beschriftung": "Mein Kind schwimmt sicher", "typ": "ja_nein", "optionen": [String](), "pflicht": true],
        ["schluessel": "tshirt", "beschriftung": "T-Shirt-Grösse", "typ": "auswahl", "optionen": ["128", "140", "152", "164"], "pflicht": true],
        ["schluessel": "bemerkung", "beschriftung": "Bemerkungen für die Leitung", "typ": "text", "optionen": [String](), "pflicht": false],
    ] }

    private func participants(_ me: Person) -> [[String: Any]] {
        let kids = me.children
        func registration(_ key: String) -> Any {
            guard let stored = eventState.registrations[key] else { return NSNull() }
            return stored
        }
        if kids.isEmpty {
            return [["kindId": NSNull(), "name": me.name, "konto": [["schluessel": "name", "beschriftung": "Name", "wert": me.name]],
                     "anmeldung": registration(me.id)]]
        }
        return kids.map { kid in
            ["kindId": kid.id, "name": kid.firstName,
             "konto": [["schluessel": "name", "beschriftung": "Name", "wert": me.name],
                       ["schluessel": "kind", "beschriftung": "Kind", "wert": "Jahrgang 2016"],
                       ["schluessel": "stufe", "beschriftung": "Stufe", "wert": Self.unitNames[kid.unit]?.0 ?? ""]] as [[String: Any]],
             "anmeldung": registration(kid.id)] as [String: Any]
        }
    }

    private mutating func occasionRoutes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        guard route.first == Self.occasion else { return .notFound }
        let closed = failure == "occasionClosed"
        switch (request.method, route.dropFirst().first) {
        case ("GET", nil):
            return .json(200, [
                "id": Self.occasion, "terminId": Self.camp2027, "titel": "Sommerlager Beispiel 2027", "ganztaegig": true,
                "tagVon": DateFormats.calendarDayText(Self.date(days: 40, hour: 2)), "tagBis": DateFormats.calendarDayText(Self.date(days: 47, hour: 2)),
                "anmeldungOffen": !closed, "frist": DateFormats.timestampText(Self.date(days: 30, hour: 12)),
                "anmeldungFuer": me.children.isEmpty ? "person" : "kind", "felder": Self.occasionFields, "teilnehmende": participants(me),
            ] as [String: Any])
        case ("PUT", "anmeldung"):
            if closed { return .error(409, "ANMELDUNG_GESCHLOSSEN", "Die Anmeldung ist geschlossen.") }
            let answers = request.body["antworten"] as? [String: Any] ?? [:]
            var errors: [[String: String]] = []
            if answers["schwimmt"] == nil { errors.append(["code": "PFLICHT", "schluessel": "schwimmt"]) }
            if answers["tshirt"] == nil { errors.append(["code": "PFLICHT", "schluessel": "tshirt"]) }
            guard errors.isEmpty else {
                return .json(400, ["code": "ANTWORTEN_UNGUELTIG", "message": "Die Antworten sind ungültig.", "fehler": errors])
            }
            let key = (request.body["kindId"] as? String) ?? me.id
            let stored: [String: Any] = ["id": nextId(), "status": "angemeldet", "antworten": answers, "geaendertAm": DateFormats.timestampText(.now)]
            eventState.registrations[key] = stored
            return .json(200, stored)
        case ("DELETE", "anmeldung"):
            eventState.registrations[request.query["kindId"] ?? me.id] = nil
            return .noContent
        default:
            return .notFound
        }
    }
}
#endif
