#if DEBUG
import Foundation
import Synchronization
import SwiftUI

/// Launch arguments of the UI-test suite (DEBUG only; none of this exists in Release or Prod builds).
///
/// - `-UITestBackend YES`: the app talks to `UITestBackend` instead of the network. Without it nothing changes.
/// - `-UITestFailure offline|server|unauthorized|outdated|empty`: failure injection for the state screens (offline:
///   first request; server: first program list 500; unauthorized: first program detail 401; outdated: every request 426;
///   empty: no programs).
/// - `-UITestSignedIn <username>`: cold start with a stored session of that persona (goes through `get-session`).
/// - `-UITestLocked YES`: switches the app lock on and shows the lock screen once; «Entsperren» unlocks without Face ID.
/// - `-AppleInterfaceStyle Dark`: dark mode; iOS apps do not apply this argument by themselves.
nonisolated enum UITestLaunch {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-UITestBackend") }
    static var failure: String? { UserDefaults.standard.string(forKey: "UITestFailure") }
    static var signedInAs: String? { UserDefaults.standard.string(forKey: "UITestSignedIn") }
    static var startsLocked: Bool { UserDefaults.standard.bool(forKey: "UITestLocked") }

    static var colorScheme: ColorScheme? {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : nil
    }

    /// The real `AppState` (APIClient, decoding, phases), wired to the simulated backend. No keychain, no real server.
    @MainActor static func appState() -> AppState {
        let configuration = AppConfiguration(
            environment: .dev, infoDictionary: [AppConfiguration.baseURLKey: "https://ui-test.example.org"]
        )
        let cookies = signedInAs == nil ? [:] : [UITestBackend.sessionCookie: UITestBackend.seededToken]
        return AppState(
            configuration: configuration, cookieStore: FixedCookieStore(cookies: cookies),
            session: APIClient.makeSession(protocolClasses: [UITestBackend.self])
        )
    }
}

/// Cookies live only in the `APIClient` during a UI-test launch; nothing reaches the keychain or the next launch.
private nonisolated struct FixedCookieStore: CookieStore {
    let cookies: [String: String]
    func read() -> [String: String] { cookies }
    func write(_ cookies: [String: String]) {}
    func delete() {}
}

/// Simulated, stateful in-memory server for the UI tests. Serves every endpoint the app uses with fictional data
/// (invented names, `example.org`). The persona follows the username typed at sign-in: `eltern…` parent with two
/// children, `leitung…` unit leader, `neu…` first sign-in; anything else is a parent. Any non-empty password is accepted; there are no credentials anywhere.
nonisolated final class UITestBackend: URLProtocol {
    static let sessionCookie = "cevi_session"
    static let seededToken = "seeded"
    private static let world = Mutex(World(failure: UITestLaunch.failure, seededUser: UITestLaunch.signedInAs))

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let incoming = World.Request(
            method: request.httpMethod ?? "GET",
            path: url.path(),
            query: Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a },
            cookies: Self.cookies(request.value(forHTTPHeaderField: "Cookie")),
            body: Self.body(of: request)
        )
        let reply = Self.world.withLock { $0.handle(incoming) }
        guard let status = reply.status else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var headers = ["Content-Type": "application/json"]
        if let cookie = reply.setCookie { headers["Set-Cookie"] = cookie }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func cookies(_ header: String?) -> [String: String] {
        var result: [String: String] = [:]
        for pair in (header ?? "").split(separator: ";") {
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    /// URLSession hands the body to a protocol as a stream.
    private static func body(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

// MARK: - World

/// `null` in JSONSerialization terms.
private nonisolated func orNull(_ value: Any?) -> Any { value ?? NSNull() }

/// State of the simulated server for one app launch.
private nonisolated struct World {
    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let cookies: [String: String]
        let body: [String: Any]
    }

    struct Reply {
        /// `nil`: no connection.
        let status: Int?
        var body = Data()
        var setCookie: String?

        static let offline = Reply(status: nil)

        static func json(_ status: Int, _ object: Any, setCookie: String? = nil) -> Reply {
            Reply(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), setCookie: setCookie)
        }

        static func error(_ status: Int, _ code: String, _ message: String) -> Reply {
            json(status, ["code": code, "message": message])
        }

        static let noContent = Reply(status: 204)
        static let notFound = error(404, "NICHT_GEFUNDEN", "Nicht gefunden.")
    }

    enum Kind { case parent, leader, newcomer }

    struct Person {
        let id: String
        let username: String
        let kind: Kind
        let name: String
        let ceviName: String?
        var mustChangePassword: Bool
        var privacyRead: Date?
        var phone: String?
        var pushChat = true
        var pushPrograms = true
        var pushRegistrations = true

        var isParent: Bool { kind == .parent || kind == .newcomer }
        var roles: [(unit: String, type: String)] {
            kind == .leader ? [(Ids.jungschar, "stufenleitung"), (Ids.froeschli, "leitung")] : []
        }
        var children: [Kid] { isParent ? World.kids.filter { $0.parent == Ids.parent } : [] }
        var units: [String] {
            switch kind {
            case .parent, .newcomer: [Ids.jungschar]
            case .leader: [Ids.jungschar, Ids.froeschli]
            }
        }
        func leads(_ unit: String) -> Bool { roles.contains { $0.unit == unit } }
    }

    struct Kid {
        let id: String
        let firstName: String
        let lastName: String
        let unit: String
        let parent: String?
    }

    struct Program {
        let id: String
        let title: String
        var status: String
        var visibility: String
        var units: [String]
        let isAllDay: Bool
        /// Days from today.
        let day: Int
        var length = 1
        var startHour = 14
        var endHour = 17
        var location: String?
        var description: String?
        var meetingPoint: String?
        var bring: String?
        var answers: [String: String] = [:]
        var leaderAnswers: [String: String] = [:]

        var start: Date { World.date(days: day, hour: isAllDay ? 0 : startHour) }
        var isOpen: Bool { status == "aktiv" && start > .now }
    }

    struct Message {
        let number: Int
        let text: String
        let createdAt: Date
        let author: String
        var program: String?
        var id: String { String(format: "00000000-0000-7000-8000-%012x", number) }
    }

    struct Chat {
        let id: String
        let unit: String
        /// `nil` for the group chat of the unit.
        let parent: String?
        var messages: [Message]
        var unread: Int
    }

    enum Ids {
        static let jungschar = "00000000-0000-0000-0000-0000000000b1"
        static let froeschli = "00000000-0000-0000-0000-0000000000b2"
        static let parent = "00000000-0000-0000-0000-000000000031"
        static let otherParent = "00000000-0000-0000-0000-000000000033"
        static let newcomer = "00000000-0000-0000-0000-000000000032"
        static let leader = "00000000-0000-0000-0000-000000000021"
        static let forest = "00000000-0000-0000-0000-0000000000a1"
        static let candles = "00000000-0000-0000-0000-0000000000a2"
        static let weekend = "00000000-0000-0000-0000-0000000000a3"
        static let games = "00000000-0000-0000-0000-0000000000a4"
        static let groupChat = "00000000-0000-0000-0000-0000000000c1"
        static let otherDirectChat = "00000000-0000-0000-0000-0000000000c2"
    }

    static let kids = [
        Kid(id: "00000000-0000-0000-0000-000000000011", firstName: "Lena", lastName: "Beispiel", unit: Ids.jungschar, parent: Ids.parent),
        Kid(id: "00000000-0000-0000-0000-000000000012", firstName: "Noah", lastName: "Beispiel", unit: Ids.jungschar, parent: Ids.parent),
        Kid(id: "00000000-0000-0000-0000-000000000013", firstName: "Lara", lastName: "Muster", unit: Ids.jungschar, parent: Ids.otherParent),
        Kid(id: "00000000-0000-0000-0000-000000000014", firstName: "Tim", lastName: "Muster", unit: Ids.jungschar, parent: Ids.otherParent),
        Kid(id: "00000000-0000-0000-0000-000000000015", firstName: "Mia", lastName: "Muster", unit: Ids.froeschli, parent: Ids.otherParent),
    ]

    static let unitNames = [Ids.jungschar: ("Jungschar", "JS"), Ids.froeschli: ("Fröschli", "FR")]

    /// Authors and contacts: id → (name, Cevi name, unit leader).
    static let people: [String: (name: String, ceviName: String?, unitLeader: Bool)] = [
        Ids.leader: ("Jan Muster", "Biber", true),
        Ids.parent: ("Eva Beispiel", nil, false),
        Ids.otherParent: ("Sara Muster", nil, false),
        Ids.newcomer: ("Mara Beispiel", nil, false),
    ]

    var failure: String?
    var accounts: [String: Person] = [:]
    var sessions: [String: String] = [:]
    var programs: [Program]
    var chats: [Chat]
    var counter = 0x100

    init(failure: String?, seededUser: String?) {
        self.failure = failure
        if let seededUser { sessions[UITestBackend.seededToken] = seededUser }
        let kids = Self.kids
        programs = [
            Program(id: Ids.forest, title: "Waldnachmittag", status: "aktiv", visibility: "eltern", units: [Ids.jungschar],
                    isAllDay: false, day: 3, location: "Waldhütte Beispielwald", description: "Wir bauen ein Floss.",
                    meetingPoint: "Bahnhof Beispielstadt", bring: "Regenjacke und Zvieri"),
            Program(id: Ids.candles, title: "Kerzenziehen", status: "abgesagt", visibility: "eltern", units: [Ids.jungschar],
                    isAllDay: false, day: 10, endHour: 16, location: "Gemeindehaus Beispielstadt", answers: [kids[0].id: "ja"]),
            Program(id: Ids.weekend, title: "Herbstweekend", status: "pruefen", visibility: "eltern",
                    units: [Ids.jungschar, Ids.froeschli], isAllDay: true, day: 20, length: 2, location: "Lagerhaus Beispieltal"),
            Program(id: Ids.games, title: "Spielnachmittag", status: "aktiv", visibility: "eltern", units: [Ids.jungschar],
                    isAllDay: false, day: -2, location: "Gemeindehaus Beispielstadt",
                    answers: [kids[0].id: "ja", kids[1].id: "nein", kids[2].id: "ja"], leaderAnswers: [Ids.leader: "ja"]),
        ]
        chats = []
        // 22 messages: one page (20) plus older ones, so «Ältere Nachrichten laden» has something to load.
        var group: [Message] = []
        for index in 1...20 {
            group.append(message(text: "Info \(index): Treffpunkt wie immer beim Gemeindehaus.", author: Ids.leader,
                                 minutesAgo: 3000 - index * 60))
        }
        group.append(message(text: "Danke, Lena ist dabei.", author: Ids.parent, minutesAgo: 120))
        group.append(message(text: "Bitte Regenjacke mitnehmen.", author: Ids.leader, minutesAgo: 60, program: Ids.forest))
        let direct = [message(text: "Tim kommt am Samstag etwas später.", author: Ids.otherParent, minutesAgo: 600)]
        chats = [
            Chat(id: Ids.groupChat, unit: Ids.jungschar, parent: nil, messages: group, unread: 2),
            Chat(id: Ids.otherDirectChat, unit: Ids.jungschar, parent: Ids.otherParent, messages: direct, unread: 1),
        ]
    }

    // MARK: Router

    mutating func handle(_ request: Request) -> Reply {
        if let injected = injectedFailure(request) { return injected }
        let parts = request.path.split(separator: "/").map(String.init)
        if parts.starts(with: ["api", "auth"]) { return auth(request, Array(parts.dropFirst(2))) }
        guard parts.starts(with: ["api", "v1"]) else { return .notFound }
        guard let token = request.cookies[UITestBackend.sessionCookie], let username = sessions[token] else {
            return .error(401, "NICHT_ANGEMELDET", "Bitte melde dich an.")
        }
        let me = account(username)
        let route = Array(parts.dropFirst(2))
        // Image routes (profile images, unit logos): no pictures in the UI tests; the app shows initials and the Cevi logo.
        if route.contains("bild") || route.last == "logo" { return .notFound }
        switch (request.method, route.first) {
        case ("GET", "ich"): return .json(200, profile(me))
        case ("POST", "ich") where route.last == "datenschutz":
            accounts[username]?.privacyRead = .now
            return .noContent
        case ("PATCH", "ich"): return patchProfile(username, request.body)
        case (_, "programme"): return programmes(request, Array(route.dropFirst()), me)
        case ("GET", "stufen") where route.count == 1:
            return .json(200, ["stufen": [Ids.jungschar, Ids.froeschli].map(unit)])
        case (_, "chats"): return chatRoutes(request, Array(route.dropFirst()), me)
        case ("PUT", "push-token"): return .noContent
        default: return .notFound
        }
    }

    /// One-shot failures hit the first matching request; `outdated` and `empty` hold for the whole launch.
    private mutating func injectedFailure(_ request: Request) -> Reply? {
        let isProgramList = request.method == "GET" && request.path == "/api/v1/programme"
        let isProgramDetail = request.method == "GET" && request.path.hasPrefix("/api/v1/programme/") && request.path.split(separator: "/").count == 4
        switch failure {
        case "offline":
            failure = nil
            return .offline
        case "outdated":
            return .error(426, "APP_VERALTET", "Bitte die App aktualisieren.")
        case "server" where isProgramList:
            failure = nil
            return .json(500, [String: String]())
        case "unauthorized" where isProgramDetail:
            failure = nil
            return .error(401, "NICHT_ANGEMELDET", "Bitte melde dich an.")
        case "empty" where isProgramList:
            return .json(200, ["programme": [Any]()])
        default:
            return nil
        }
    }

    // MARK: Auth

    private mutating func auth(_ request: Request, _ route: [String]) -> Reply {
        let session = request.cookies[UITestBackend.sessionCookie].flatMap { sessions[$0] }
        switch route.joined(separator: "/") {
        case "sign-in/username":
            let username = (request.body["username"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard !username.isEmpty, !(request.body["password"] as? String ?? "").isEmpty else {
                return .error(401, "INVALID_USERNAME_OR_PASSWORD", "Invalid username or password")
            }
            return signedIn(username)
        case "get-session":
            guard let session else { return Reply(status: 200, body: Data("null".utf8)) }
            return .json(200, ["session": ["userId": account(session).id], "user": ["id": account(session).id]])
        case "change-password":
            guard let session else { return .error(401, "UNAUTHORIZED", "Unauthorized") }
            let new = request.body["newPassword"] as? String ?? ""
            if new.count < 12 { return .error(400, "PASSWORD_TOO_SHORT", "Password too short") }
            if new.lowercased().contains("passwort") { return .error(400, "PASSWORD_COMPROMISED", "Password compromised") }
            accounts[session]?.mustChangePassword = false
            return .json(200, ["token": NSNull()])
        case "sign-out":
            if let token = request.cookies[UITestBackend.sessionCookie] { sessions[token] = nil }
            return .json(200, ["success": true], setCookie: "\(UITestBackend.sessionCookie)=; Path=/; Max-Age=0")
        default:
            return .notFound
        }
    }

    private mutating func signedIn(_ username: String) -> Reply {
        let token = nextToken()
        sessions[token] = username
        _ = account(username)
        return .json(200, ["redirect": false], setCookie: "\(UITestBackend.sessionCookie)=\(token); Path=/; HttpOnly")
    }

    private mutating func nextToken() -> String {
        counter += 1
        return "t\(counter)"
    }

    /// The account of a username, created on first use from its prefix.
    @discardableResult
    private mutating func account(_ username: String) -> Person {
        if let known = accounts[username] { return known }
        let person: Person = if username.hasPrefix("leitung") {
            Person(id: Ids.leader, username: username, kind: .leader, name: "Jan Muster", ceviName: "Biber",
                   mustChangePassword: false, privacyRead: .now, phone: "000 000 00 01")
        } else if username.hasPrefix("neu") {
            Person(id: Ids.newcomer, username: username, kind: .newcomer, name: "Mara Beispiel", ceviName: nil,
                   mustChangePassword: true, privacyRead: nil)
        } else {
            Person(id: Ids.parent, username: username, kind: .parent, name: "Eva Beispiel", ceviName: nil,
                   mustChangePassword: false, privacyRead: .now)
        }
        accounts[username] = person
        return person
    }

    // MARK: Profile

    private func profile(_ me: Person) -> [String: Any] {
        var object: [String: Any] = [
            "id": me.id, "name": me.name, "ceviName": orNull(me.ceviName), "benutzername": me.username,
            "mussPasswortAendern": me.mustChangePassword,
            "datenschutzGelesenAm": orNull(me.privacyRead.map(DateFormats.timestampText)),
            "telefon": orNull(me.phone), "bildUrl": NSNull(), "pushChat": me.pushChat, "pushProgramme": me.pushPrograms,
            "admin": false,
            "rollen": me.roles.map { ["stufeId": $0.unit, "typ": $0.type] },
            "stufen": me.units.map(unit),
            "kinder": me.children.map { ["id": $0.id, "vorname": $0.firstName, "nachname": $0.lastName, "stufeId": $0.unit] },
        ]
        if !me.roles.isEmpty { object["pushAnmeldungen"] = me.pushRegistrations }
        return object
    }

    private mutating func patchProfile(_ username: String, _ body: [String: Any]) -> Reply {
        if let value = body["pushChat"] as? Bool { accounts[username]?.pushChat = value }
        if let value = body["pushProgramme"] as? Bool { accounts[username]?.pushPrograms = value }
        if let value = body["pushAnmeldungen"] as? Bool { accounts[username]?.pushRegistrations = value }
        if body.keys.contains("telefon") { accounts[username]?.phone = body["telefon"] as? String }
        return .noContent
    }

    private func unit(_ id: String) -> [String: Any] {
        ["id": id, "name": Self.unitNames[id]?.0 ?? "", "kuerzel": Self.unitNames[id]?.1 ?? ""]
    }

    // MARK: Programs

    private mutating func programmes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        guard let id = route.first else {
            guard request.method == "GET" else { return .notFound }
            let visible = programs.filter { $0.day + $0.length > 0 && isVisible($0, to: me) }.sorted { $0.start < $1.start }
            return .json(200, ["programme": visible.map { program($0, for: me) }])
        }
        guard let index = programs.firstIndex(where: { $0.id == id }), isVisible(programs[index], to: me) else { return .notFound }
        switch (request.method, route.dropFirst().first) {
        case ("GET", nil):
            return .json(200, program(programs[index], for: me))
        case ("GET", "kontakte"):
            let leader = Self.people[Ids.leader]!
            return .json(200, ["kontakte": [["id": Ids.leader, "name": leader.name, "ceviName": orNull(leader.ceviName),
                                             "bildUrl": NSNull(), "telefon": "000 000 00 01"]]])
        case ("GET", "teilnahmen"):
            guard programs[index].units.contains(where: me.leads) else { return .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.") }
            return .json(200, participation(programs[index]))
        case ("PUT", "teilnahmen"):
            guard let child = route.last, me.children.contains(where: { $0.id == child }) else {
                return .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.")
            }
            guard programs[index].isOpen else {
                return .error(409, "ANMELDUNG_GESCHLOSSEN", "Die Anmeldung ist geschlossen.")
            }
            programs[index].answers[child] = request.body["status"] as? String
            return .noContent
        case ("PUT", "leitung"):
            guard programs[index].units.contains(where: me.leads) else { return .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.") }
            guard programs[index].start > .now else { return .error(409, "PROGRAMM_BEGONNEN", "Das Programm hat begonnen.") }
            programs[index].leaderAnswers[me.id] = request.body["status"] as? String
            return .noContent
        case ("PUT", "zuordnung"):
            guard !me.roles.filter({ $0.type == "stufenleitung" }).isEmpty else {
                return .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.")
            }
            programs[index].units = request.body["stufen"] as? [String] ?? []
            programs[index].visibility = request.body["sichtbarkeit"] as? String ?? "intern"
            return .noContent
        default:
            return .notFound
        }
    }

    private func isVisible(_ program: Program, to me: Person) -> Bool {
        if me.isParent {
            return program.visibility == "eltern" && program.units.contains { unit in me.children.contains { $0.unit == unit } }
        }
        return program.units.contains(where: me.leads)
    }

    private func program(_ p: Program, for me: Person) -> [String: Any] {
        let kids = me.children.filter { p.units.contains($0.unit) }
        var object: [String: Any] = [
            "id": p.id, "titel": p.title, "status": p.status, "sichtbarkeit": p.visibility, "ganztaegig": p.isAllDay,
            "stufen": p.units.map { ["id": $0, "name": Self.unitNames[$0]?.0 ?? ""] },
            "googleOrt": orNull(p.location),
            "kinder": kids.map { ["id": $0.id, "vorname": $0.firstName, "status": orNull(p.answers[$0.id])] },
            "treffpunkt": orNull(p.meetingPoint), "schlussOrt": orNull(p.meetingPoint), "mitnehmen": orNull(p.bring),
            "teilnahmeOffen": p.isOpen,
        ]
        if p.isAllDay {
            object["tagVon"] = DateFormats.calendarDayText(Self.date(days: p.day, hour: 2))
            object["tagBis"] = DateFormats.calendarDayText(Self.date(days: p.day + p.length - 1, hour: 2))
        } else {
            object["beginn"] = DateFormats.timestampText(Self.date(days: p.day, hour: p.startHour))
            object["ende"] = DateFormats.timestampText(Self.date(days: p.day, hour: p.endHour))
            object["schlussZeit"] = String(format: "%02d:00", p.endHour)
        }
        if p.units.contains(where: me.leads) {
            object["googleBeschreibung"] = orNull(p.description)
            if me.kind == .leader { object["eigeneAnmeldung"] = p.leaderAnswers[me.id] ?? "offen" }
        }
        return object
    }

    private func participation(_ p: Program) -> [String: Any] {
        let children = Self.kids.filter { p.units.contains($0.unit) }.map { kid -> [String: Any] in
            ["id": kid.id, "vorname": kid.firstName, "nachname": kid.lastName, "stufeId": kid.unit, "status": p.answers[kid.id] ?? "offen"]
        }
        let leader = Self.people[Ids.leader]!
        let leaders: [[String: Any]] = p.units.contains(Ids.jungschar) ? [[
            "id": Ids.leader, "name": leader.name, "ceviName": orNull(leader.ceviName), "stufeId": Ids.jungschar,
            "rolle": "stufenleitung", "status": p.leaderAnswers[Ids.leader] ?? "offen",
        ]] : []
        return ["zahlen": ["kinder": counts(children), "leitende": counts(leaders)], "kinder": children, "leitende": leaders]
    }

    private func counts(_ rows: [[String: Any]]) -> [String: Int] {
        let answers = rows.map { $0["status"] as? String }
        return ["ja": answers.count { $0 == "ja" }, "nein": answers.count { $0 == "nein" }, "offen": answers.count { $0 == "offen" }]
    }

    // MARK: Chats

    private mutating func chatRoutes(_ request: Request, _ route: [String], _ me: Person) -> Reply {
        let mine = chats.indices.filter { isMember(chats[$0], me) }
        guard let id = route.first else {
            return .json(200, ["chats": mine.map { summary(chats[$0], me) }])
        }
        if id == "direkt", request.method == "POST" {
            guard let unitId = request.body["stufeId"] as? String, me.isParent else { return .error(403, "KEIN_ZUGRIFF", "Kein Zugriff.") }
            if let existing = chats.first(where: { $0.unit == unitId && $0.parent == me.id }) { return .json(200, ["id": existing.id]) }
            counter += 1
            let chatId = String(format: "00000000-0000-0000-0000-%012x", counter)
            chats.append(Chat(id: chatId, unit: unitId, parent: me.id, messages: [], unread: 0))
            return .json(200, ["id": chatId])
        }
        guard let index = mine.first(where: { chats[$0].id == id }) else { return .notFound }
        switch (request.method, route.dropFirst().first) {
        case ("GET", "nachrichten"):
            let sorted = chats[index].messages.sorted { $0.number > $1.number }
            let older = request.query["vor"].flatMap { cursor in sorted.firstIndex { $0.id == cursor } }.map { $0 + 1 } ?? 0
            let page = Array(sorted.dropFirst(older).prefix(20))
            let hasMore = older + page.count < sorted.count
            return .json(200, ["nachrichten": page.map { message($0, me) }, "naechster": orNull(hasMore ? page.last?.id : nil)])
        case ("POST", "nachrichten"):
            let text = (request.body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 2000 else { return .error(400, "UNGUELTIG", "Die Nachricht ist leer oder zu lang.") }
            var new = message(text: text, author: me.id, minutesAgo: 0)
            new.program = request.body["programmId"] as? String
            chats[index].messages.append(new)
            return .noContent
        case ("PUT", "gelesen"):
            chats[index].unread = 0
            return .noContent
        default:
            return .notFound
        }
    }

    private func isMember(_ chat: Chat, _ me: Person) -> Bool {
        if let parent = chat.parent { return parent == me.id || me.roles.contains { $0.unit == chat.unit && $0.type == "stufenleitung" } }
        return me.units.contains(chat.unit) && (me.isParent || me.roles.contains { $0.unit == chat.unit })
    }

    private func person(_ id: String) -> [String: Any] {
        let person = Self.people[id]
        return ["id": id, "name": person?.name ?? "", "ceviName": orNull(person?.ceviName)]
    }

    private func summary(_ chat: Chat, _ me: Person) -> [String: Any] {
        let last = chat.messages.max { $0.number < $1.number }
        return [
            "id": chat.id, "typ": chat.parent == nil ? "stufe" : "direkt", "stufe": unit(chat.unit),
            "eltern": orNull(chat.parent.map(person)), "stufenleitung": [person(Ids.leader)], "ungelesen": chat.unread,
            "letzteNachricht": orNull(last.map { [
                "text": String($0.text.prefix(120)), "erstelltAm": DateFormats.timestampText($0.createdAt),
                "eigene": $0.author == me.id, "autor": person($0.author),
            ] as [String: Any] }),
        ]
    }

    private func message(_ m: Message, _ me: Person) -> [String: Any] {
        var author = person(m.author)
        author["bildUrl"] = NSNull()
        author["stufenleitung"] = Self.people[m.author]?.unitLeader ?? false
        var object: [String: Any] = [
            "id": m.id, "text": m.text, "erstelltAm": DateFormats.timestampText(m.createdAt), "eigene": m.author == me.id, "autor": author,
        ]
        if let program = m.program, let title = programs.first(where: { $0.id == program })?.title {
            object["programm"] = ["id": program, "titel": title]
        }
        return object
    }

    private mutating func message(text: String, author: String, minutesAgo: Int, program: String? = nil) -> Message {
        counter += 1
        return Message(number: counter, text: text, createdAt: .now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
                       author: author, program: program)
    }

    // MARK: Dates

    /// Today (Swiss calendar day) plus days and hours.
    static func date(days: Int, hour: Int) -> Date {
        let today = DateFormats.calendar.startOfDay(for: .now)
        return DateFormats.calendar.date(byAdding: .day, value: days, to: today)!.addingTimeInterval(TimeInterval(hour * 3600))
    }
}
#endif
