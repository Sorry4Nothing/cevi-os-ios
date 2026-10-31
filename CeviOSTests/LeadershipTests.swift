import Foundation
import Testing
@testable import CeviOS

struct LeadershipPermissionsTests {
    private let unitA = UUID(), unitB = UUID()

    private func profile(admin: Bool = false, roles: [(UUID, String)] = []) throws -> Profile {
        let rolesJSON = roles.map { #"{"stufeId":"\#($0.0.uuidString)","typ":"\#($0.1)"}"# }.joined(separator: ",")
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"T","ceviName":null,"benutzername":"t","mussPasswortAendern":false,
         "datenschutzGelesenAm":null,"telefon":null,"bildUrl":null,"pushChat":true,"pushProgramme":true,"admin":\(admin),
         "zweiterFaktor":false,"rollen":[\(rolesJSON)],"stufen":[],"kinder":[]}
        """
        return try JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
    }

    private func program(units: [UUID], own: String? = nil, start: String = "2099-01-01T10:00:00Z") throws -> Program {
        let unitsJSON = units.map { #"{"id":"\#($0.uuidString)","name":"S"}"# }.joined(separator: ",")
        let ownJSON = own.map { #","eigeneAnmeldung":"\#($0)""# } ?? ""
        let json = """
        {"id":"22222222-2222-2222-2222-222222222222","titel":"T","status":"aktiv","sichtbarkeit":"eltern","ganztaegig":false,
         "beginn":"\(start)","ende":"2099-01-01T12:00:00Z","tagVon":null,"tagBis":null,"googleOrt":null,"stufen":[\(unitsJSON)],
         "googleBeschreibung":null,"kinder":[]\(ownJSON)}
        """
        return try JSONDecoder.api.decode(Program.self, from: Data(json.utf8))
    }

    @Test func parentsGetNoLeadershipControls() throws {
        let permissions = LeadershipPermissions(profile: try profile())
        #expect(!permissions.canSeeOverview(of: try program(units: [unitA])))
        #expect(!permissions.canAssign)
        #expect(permissions.attendanceUnits(from: []).isEmpty)
    }

    @Test func leadersSeeTheOverviewOfTheirUnitsButCannotAssign() throws {
        let permissions = LeadershipPermissions(profile: try profile(roles: [(unitA, "leitung")]))
        #expect(permissions.canSeeOverview(of: try program(units: [unitA])))
        #expect(!permissions.canSeeOverview(of: try program(units: [unitB])))
        #expect(!permissions.canAssign)
    }

    @Test func unitLeadersMayOnlyChangeTheirOwnUnits() throws {
        let permissions = LeadershipPermissions(profile: try profile(roles: [(unitA, "stufenleitung")]))
        #expect(permissions.canAssign)
        #expect(permissions.canSaveAssignment(oldUnits: [], newUnits: [unitA], oldVisibility: .parents, newVisibility: .parents))
        #expect(!permissions.canSaveAssignment(oldUnits: [], newUnits: [unitB], oldVisibility: .parents, newVisibility: .parents))
        // Keeping a foreign unit unchanged is fine as long as visibility stays.
        #expect(permissions.canSaveAssignment(oldUnits: [unitB], newUnits: [unitA, unitB], oldVisibility: .parents, newVisibility: .parents))
        // Changing visibility needs all units to be theirs.
        #expect(!permissions.canSaveAssignment(oldUnits: [unitB], newUnits: [unitA, unitB], oldVisibility: .parents, newVisibility: .leaders))
    }

    @Test func adminsMayDoEverything() throws {
        let permissions = LeadershipPermissions(profile: try profile(admin: true))
        #expect(permissions.canAssign)
        #expect(permissions.canSaveAssignment(oldUnits: [unitB], newUnits: [], oldVisibility: .parents, newVisibility: .internalOnly))
    }

    @Test func noUnitsOnlyAllowsInternalVisibility() {
        #expect(LeadershipPermissions.isValidAssignment(units: [], visibility: .internalOnly))
        #expect(!LeadershipPermissions.isValidAssignment(units: [], visibility: .parents))
        #expect(LeadershipPermissions.isValidAssignment(units: [UUID()], visibility: .parents))
    }

    @Test func ownRegistrationNeedsTheKeyAndAProgramThatHasNotStarted() throws {
        let permissions = LeadershipPermissions(profile: try profile(roles: [(unitA, "leitung")]))
        #expect(permissions.canRegisterAsLeader(for: try program(units: [unitA], own: "offen")))
        #expect(!permissions.canRegisterAsLeader(for: try program(units: [unitA])))
        #expect(!permissions.canRegisterAsLeader(for: try program(units: [unitA], own: "ja", start: "2020-01-01T10:00:00Z")))
    }

    @Test func attendanceUnitsAreTheOnesTheyLead() throws {
        let json = #"[{"id":"\#(unitA.uuidString)","name":"A","kuerzel":"A"},{"id":"\#(unitB.uuidString)","name":"B","kuerzel":"B"}]"#
        let units = try JSONDecoder.api.decode([UnitSummary].self, from: Data(json.utf8))
        let permissions = LeadershipPermissions(profile: try profile(roles: [(unitA, "leitung")]))
        #expect(permissions.attendanceUnits(from: units).map(\.id) == [unitA])
    }
}

struct LeadershipModelsTests {
    @Test func presenceBodyWritesNullToTakeAnEntryBack() throws {
        let take = String(decoding: try JSONEncoder().encode(PresenceBody(present: nil)), as: UTF8.self)
        #expect(take == #"{"da":null}"#)
        let set = String(decoding: try JSONEncoder().encode(PresenceBody(present: true)), as: UTF8.self)
        #expect(set == #"{"da":true}"#)
    }

    @Test func attendanceOverviewIsDecodedWithFlatRows() throws {
        let json = """
        {"stufe":{"id":"11111111-1111-1111-1111-111111111111","name":"A"},
         "anlaesse":[{"id":"22222222-2222-2222-2222-222222222222","titel":"T","ganztaegig":false,"beginn":"2026-10-01T10:00:00Z",
           "ende":"2026-10-01T12:00:00Z","tagVon":null,"tagBis":null,"vergangen":true,"erfassbar":true}],
         "zahlen":{"kinder":{"da":1,"von":2,"prozent":50},"leitende":{"da":0,"von":0,"prozent":null}},"naechster":null,
         "kinder":[{"id":"33333333-3333-3333-3333-333333333333","vorname":"Mia","nachname":"M","anwesenheit":["da"],
           "zusage":["ja"],"da":1,"von":2,"prozent":50}],
         "leitende":[{"id":"44444444-4444-4444-4444-444444444444","name":"L","ceviName":null,"rolle":"leitung",
           "anwesenheit":[null],"zusage":["offen"],"da":0,"von":0,"prozent":null}]}
        """
        let overview = try JSONDecoder.api.decode(AttendanceOverview.self, from: Data(json.utf8))
        #expect(overview.events.first?.isRecordable == true)
        #expect(overview.children.first?.rows.attendance == [.present])
        #expect(overview.children.first?.rows.quota.percent == 50)
        #expect(overview.leaders.first?.rows.attendance == [nil])
        #expect(overview.leaders.first?.rows.answers == [.open])
        #expect(overview.totals.leaders.percent == nil)
    }

    @Test func participationOverviewIsDecoded() throws {
        let json = """
        {"zahlen":{"kinder":{"ja":1,"nein":0,"offen":1},"leitende":{"ja":0,"nein":0,"offen":0}},
         "kinder":[{"id":"33333333-3333-3333-3333-333333333333","vorname":"Mia","nachname":"M",
           "stufeId":"11111111-1111-1111-1111-111111111111","status":"offen"}],"leitende":[]}
        """
        let overview = try JSONDecoder.api.decode(ParticipationOverview.self, from: Data(json.utf8))
        #expect(overview.totals.children == ParticipationCounts(yes: 1, no: 0, open: 1))
        #expect(overview.children.first?.answer == .open)
    }

    @Test func startedProgramAndClosedAttendanceShowClearMessages() {
        let started = APIError.from(status: 409, data: Data(#"{"code":"PROGRAMM_BEGONNEN","message":"x"}"#.utf8))
        #expect(LeadershipMessages.message(for: started).reload)
        #expect(LeadershipMessages.message(for: started).text.contains("begonnen"))
        let closed = APIError.from(status: 409, data: Data(#"{"code":"ANWESENHEIT_GESCHLOSSEN","message":"x"}"#.utf8))
        #expect(LeadershipMessages.message(for: closed).text.contains("14 Tage"))
        #expect(LeadershipMessages.message(for: .from(status: 403, data: Data())).reload)
    }

    @Test func participationListPutsOpenFirstThenYesThenNoByName() {
        let items: [(String, OverviewAnswer)] = [("Jonas", .no), ("Mia", .yes), ("Tim", .open), ("Anna", .no), ("Elin", .open), ("Lena", .yes)]
        let sorted = ParticipationOrder.sorted(items, answer: \.1, name: \.0)
        #expect(sorted.map(\.0) == ["Elin", "Tim", "Lena", "Mia", "Anna", "Jonas"])
    }
}
