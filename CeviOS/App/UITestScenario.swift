#if DEBUG
import Foundation
import SwiftUI

/// UI-test harness (DEBUG only). `-UITestScenario <name>` starts the app on one screen with fictional fixture data
/// served by `FixtureProtocol`, so accessibility audits run on signed-in screens without a server.
nonisolated enum UITestScenario: String, CaseIterable {
    case signIn, changePassword, privacy, programList, programDetail, participationOverview, attendance
    case chatList, chat, newMessage, profile, lock, offline, empty, error

    static let current: UITestScenario? = UserDefaults.standard.string(forKey: "UITestScenario").flatMap(Self.init)

    /// `-AppleInterfaceStyle Dark` is not applied to iOS apps by itself; the harness applies it.
    static var colorScheme: ColorScheme? {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : nil
    }

    @MainActor func appState() -> AppState {
        FixtureProtocol.scenario = self
        let client = APIClient(
            baseURL: URL(string: "https://ui-test.example.org")!, appVersion: "1.0.0",
            cookieStore: NoCookieStore(), session: APIClient.makeSession(protocolClasses: [FixtureProtocol.self])
        )
        let profile = Fixtures.profile
        let state: AppState
        switch self {
        case .signIn: state = AppState(client: client, phase: .signIn)
        case .changePassword: state = AppState(client: client, phase: .changePassword(profile))
        case .privacy: state = AppState(client: client, phase: .privacy(profile))
        case .offline: state = AppState(client: client, phase: .offline)
        default: state = AppState(client: client, phase: .ready(profile))
        }
        switch self {
        case .programDetail, .participationOverview: state.pendingTarget = .program(Fixtures.programId)
        case .chat: state.pendingTarget = .chat(Fixtures.groupChatId)
        default: break
        }
        return state
    }

    @MainActor func appLock() -> AppLock { AppLock(defaults: .standard, isLocked: self == .lock) }
}

private nonisolated struct NoCookieStore: CookieStore {
    func read() -> [String: String] { [:] }
    func write(_ cookies: [String: String]) {}
    func delete() {}
}

/// Answers every request of the harness from `Fixtures`. `offline` fails all requests, `error` fails the program list.
nonisolated final class FixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var scenario: UITestScenario = .programList

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, Self.scenario != .offline else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, body) = Fixtures.reply(method: request.httpMethod ?? "GET", path: url.path(), scenario: Self.scenario)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Fictional data only: invented names, `example.org`, no real people.
nonisolated enum Fixtures {
    static let programId = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    static let groupChatId = UUID(uuidString: "00000000-0000-0000-0000-0000000000c1")!
    private static let unitId = "00000000-0000-0000-0000-0000000000b1"
    private static let meId = "00000000-0000-0000-0000-000000000001"

    private static func time(days: Int, hour: Int) -> String {
        let day = DateFormats.calendar.startOfDay(for: .now)
        return DateFormats.timestampText(day.addingTimeInterval(TimeInterval(days * 86_400 + hour * 3_600)))
    }

    private static func dayText(_ days: Int) -> String {
        DateFormats.calendarDayText(DateFormats.calendar.startOfDay(for: .now).addingTimeInterval(TimeInterval(days * 86_400 + 7_200)))
    }

    static var profile: Profile {
        // swiftlint:disable:next force_try
        try! JSONDecoder.api.decode(Profile.self, from: Data(profileJSON.utf8))
    }

    private static let profileJSON = """
    {"id":"\(meId)","name":"Lena Beispiel","ceviName":"Fuchs","benutzername":"lena.beispiel","mussPasswortAendern":false,
     "datenschutzGelesenAm":"2026-10-01T10:00:00Z","telefon":"079 000 00 00","bildUrl":null,"pushChat":true,"pushProgramme":true,
     "pushAnmeldungen":true,"admin":false,"zweiterFaktor":false,
     "rollen":[{"stufeId":"\(unitId)","typ":"stufenleitung"}],
     "stufen":[{"id":"\(unitId)","name":"Jungschar","kuerzel":"JS"}],
     "kinder":[{"id":"00000000-0000-0000-0000-000000000011","vorname":"Mia","nachname":"Beispiel","stufeId":"\(unitId)"},
               {"id":"00000000-0000-0000-0000-000000000012","vorname":"Noah","nachname":"Beispiel","stufeId":"\(unitId)"}]}
    """

    private static var programs: [String] {
        let unit = #"[{"id":"\#(unitId)","name":"Jungschar"}]"#
        let children = #"[{"id":"00000000-0000-0000-0000-000000000011","vorname":"Mia","status":"ja"},{"id":"00000000-0000-0000-0000-000000000012","vorname":"Noah","status":null}]"#
        return [
            """
            {"id":"\(programId.uuidString.lowercased())","titel":"Waldnachmittag","status":"aktiv","sichtbarkeit":"eltern","ganztaegig":false,
             "beginn":"\(time(days: 3, hour: 14))","ende":"\(time(days: 3, hour: 17))","googleOrt":"Waldhütte Beispielwald","stufen":\(unit),
             "googleBeschreibung":"Wir bauen ein Floss.","kinder":\(children),"treffpunkt":"Bahnhof Beispielstadt","schlussOrt":"Bahnhof Beispielstadt",
             "schlussZeit":"17:00","mitnehmen":"Regenjacke und Zvieri","teilnahmeOffen":true,"eigeneAnmeldung":"offen"}
            """,
            """
            {"id":"00000000-0000-0000-0000-0000000000a2","titel":"Kerzenziehen","status":"abgesagt","sichtbarkeit":"eltern","ganztaegig":false,
             "beginn":"\(time(days: 10, hour: 14))","ende":"\(time(days: 10, hour: 16))","googleOrt":"Gemeindehaus Beispielstadt","stufen":\(unit),"kinder":\(children)}
            """,
            """
            {"id":"00000000-0000-0000-0000-0000000000a3","titel":"Herbstweekend","status":"pruefen","sichtbarkeit":"eltern","ganztaegig":true,
             "tagVon":"\(dayText(20))","tagBis":"\(dayText(21))","stufen":\(unit),"kinder":[]}
            """,
        ]
    }

    private static let participation = """
    {"zahlen":{"kinder":{"ja":1,"nein":1,"offen":1},"leitende":{"ja":1,"nein":0,"offen":0}},
     "kinder":[{"id":"00000000-0000-0000-0000-000000000011","vorname":"Mia","nachname":"Beispiel","stufeId":"\(unitId)","status":"ja"},
               {"id":"00000000-0000-0000-0000-000000000012","vorname":"Noah","nachname":"Beispiel","stufeId":"\(unitId)","status":"offen"},
               {"id":"00000000-0000-0000-0000-000000000013","vorname":"Lara","nachname":"Muster","stufeId":"\(unitId)","status":"nein"}],
     "leitende":[{"id":"\(meId)","name":"Lena Beispiel","ceviName":"Fuchs","stufeId":"\(unitId)","rolle":"stufenleitung","status":"ja"}]}
    """

    private static var attendance: String {
        """
        {"stufe":{"id":"\(unitId)","name":"Jungschar"},
         "anlaesse":[{"id":"00000000-0000-0000-0000-0000000000a4","titel":"Spielnachmittag","ganztaegig":false,"beginn":"\(time(days: -2, hour: 14))",
                      "ende":"\(time(days: -2, hour: 17))","vergangen":true,"erfassbar":true},
                     {"id":"\(programId.uuidString.lowercased())","titel":"Waldnachmittag","ganztaegig":false,"beginn":"\(time(days: 3, hour: 14))",
                      "ende":"\(time(days: 3, hour: 17))","vergangen":false,"erfassbar":false}],
         "zahlen":{"kinder":{"da":1,"von":2,"prozent":50},"leitende":{"da":1,"von":1,"prozent":100}},
         "kinder":[{"id":"00000000-0000-0000-0000-000000000011","vorname":"Mia","nachname":"Beispiel","anwesenheit":["da",null],"zusage":["ja","ja"],"da":1,"von":1,"prozent":100},
                   {"id":"00000000-0000-0000-0000-000000000013","vorname":"Lara","nachname":"Muster","anwesenheit":[null,null],"zusage":["nein","offen"],"da":0,"von":1,"prozent":0}],
         "leitende":[{"id":"\(meId)","name":"Lena Beispiel","ceviName":"Fuchs","rolle":"stufenleitung","anwesenheit":["da",null],"zusage":["ja","ja"],"da":1,"von":1,"prozent":100}]}
        """
    }

    private static let leader = #"{"id":"00000000-0000-0000-0000-000000000021","name":"Jan Muster","ceviName":"Biber"}"#

    private static var chats: String {
        """
        {"chats":[
         {"id":"\(groupChatId.uuidString.lowercased())","typ":"stufe","stufe":{"id":"\(unitId)","name":"Jungschar","kuerzel":"JS"},
          "stufenleitung":[\(leader)],"ungelesen":2,
          "letzteNachricht":{"text":"Bitte Regenjacke mitnehmen.","erstelltAm":"\(time(days: 0, hour: 9))","eigene":false,"autor":\(leader)}},
         {"id":"00000000-0000-0000-0000-0000000000c2","typ":"direkt","stufe":{"id":"\(unitId)","name":"Jungschar","kuerzel":"JS"},
          "eltern":{"id":"00000000-0000-0000-0000-000000000031","name":"Sara Muster","ceviName":null},
          "stufenleitung":[\(leader)],"ungelesen":0,
          "letzteNachricht":{"text":"Danke für die Info!","erstelltAm":"\(time(days: -1, hour: 18))","eigene":true,"autor":{"id":"\(meId)","name":"Lena Beispiel","ceviName":"Fuchs"}}}]}
        """
    }

    private static var messages: String {
        """
        {"nachrichten":[
         {"id":"00000000-0000-0000-0000-0000000000d2","text":"Danke, Mia ist dabei.","erstelltAm":"\(time(days: 0, hour: 10))","eigene":true,
          "autor":{"id":"\(meId)","name":"Lena Beispiel","ceviName":"Fuchs","bildUrl":null,"stufenleitung":true}},
         {"id":"00000000-0000-0000-0000-0000000000d1","text":"Bitte Regenjacke mitnehmen.","erstelltAm":"\(time(days: 0, hour: 9))","eigene":false,
          "autor":{"id":"00000000-0000-0000-0000-000000000021","name":"Jan Muster","ceviName":"Biber","bildUrl":null,"stufenleitung":true},
          "programm":{"id":"\(programId.uuidString.lowercased())","titel":"Waldnachmittag"}}],"naechster":null}
        """
    }

    static func reply(method: String, path: String, scenario: UITestScenario) -> (Int, String) {
        let parts = path.split(separator: "/").map(String.init)
        guard method == "GET" else {
            return path.hasSuffix("/chats/direkt") ? (200, #"{"id":"00000000-0000-0000-0000-0000000000c2"}"#) : (204, "")
        }
        switch parts.dropFirst(2).first {
        case "ich": return (200, profileJSON)
        case "programme" where parts.count == 3:
            if scenario == .error { return (500, #"{"code":"INTERN"}"#) }
            return (200, #"{"programme":[\#(scenario == .empty ? "" : programs.joined(separator: ","))]}"#)
        case "programme" where parts.last == "kontakte":
            return (200, #"{"kontakte":[{"id":"00000000-0000-0000-0000-000000000021","name":"Jan Muster","ceviName":"Biber","telefon":"079 000 00 01"}]}"#)
        case "programme" where parts.last == "teilnahmen": return (200, participation)
        case "programme": return (200, programs.first { $0.contains(parts[3]) } ?? programs[0])
        case "stufen" where parts.last == "anwesenheit": return (200, attendance)
        case "stufen": return (200, #"{"stufen":[{"id":"\#(unitId)","name":"Jungschar","kuerzel":"JS"}]}"#)
        case "chats" where parts.last == "nachrichten": return (200, messages)
        case "chats": return (200, chats)
        default: return (404, "{}")
        }
    }
}
#endif
