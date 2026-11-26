import Foundation
import Testing
@testable import CeviOS

@MainActor
struct WidgetTests {
    private let now = WidgetSamples.now
    private let samples = WidgetSamples.snapshot()

    // MARK: Snapshot, store

    @Test func snapshotSurvivesTheRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WidgetStore(directory: dir)
        #expect(store.write(samples))
        #expect(store.read() == samples)
    }

    @Test func missingStoreWritesAndReadsNothing() {
        let store = WidgetStore(directory: nil)
        #expect(!store.isAvailable)
        #expect(!store.write(samples))
        #expect(store.read() == nil)
    }

    @Test func tamperedOrOldFilesAreIgnored() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WidgetStore(directory: dir)
        let file = dir.appending(path: WidgetStore.fileName)
        try Data("{not json".utf8).write(to: file)
        #expect(store.read() == nil)
        var old = samples
        old.version = 0
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(old).write(to: file)
        #expect(store.read() == nil)
        try Data(repeating: 32, count: WidgetStore.maxBytes + 1).write(to: file)
        #expect(store.read() == nil)
    }

    @Test func signOutDeletesTheDataAndRedrawsTheWidgets() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WidgetStore(directory: dir)
        store.write(samples)
        var reloads = 0
        let refresher = WidgetRefresher(store: store, reload: { reloads += 1 })
        refresher.clear()
        let after = try #require(store.read())
        #expect(after.session == .signedOut)
        #expect(after.units.isEmpty && after.events.isEmpty && after.camps.isEmpty && after.chat == nil)
        #expect(reloads == 1)
        refresher.markSignedOutIfNeeded()
        #expect(reloads == 1)
    }

    // MARK: Redaction

    /// The model has no field for names, texts or numbers: every key of the file is on this list.
    @Test func theFileHasOnlyTheAllowedFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(samples))
        var keys = Set<String>()
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] { for (k, v) in dict { keys.insert(k); walk(v) } }
            if let array = value as? [Any] { array.forEach(walk) }
        }
        walk(object)
        let allowed: Set<String> = [
            "version", "session", "updatedAt", "status", "hidesContent", "units", "events", "camps", "chat",
            "id", "name", "isChildUnit", "programs", "openAnswers", "title", "start", "end", "isAllDay", "place", "groups",
            "from", "to", "duty", "time", "important", "todosOpen", "todosTotal", "overdueCount", "tasks", "due", "isOverdue",
            "laterCount", "doneThisWeek", "unread", "chats",
        ]
        #expect(keys.subtracting(allowed).isEmpty)
        for forbidden in ["phone", "telefon", "message", "text", "firstName", "lastName", "child", "person", "address"] {
            #expect(!keys.contains { $0.localizedCaseInsensitiveContains(forbidden) && $0 != "isChildUnit" })
        }
    }

    private func profile() throws -> Profile {
        let unit = WidgetSamples.unitId.uuidString
        let json = """
        {"id":"22222222-2222-2222-2222-222222222222","name":"Erika Vollname","ceviName":"Flinke","benutzername":"e.vollname","mussPasswortAendern":false,
         "datenschutzGelesenAm":null,"telefon":"+41 79 123 45 67","bildUrl":null,"pushChat":true,"pushProgramme":true,"geschlecht":null,
         "abteilungsleitung":false,"entwickler":false,"clientArt":"web","rechte":[],"rollen":[],
         "stufen":[{"id":"\(unit)","name":"Wölfe","kuerzel":"W"}],
         "kinder":[{"id":"33333333-3333-3333-3333-333333333333","vorname":"Maximilian","nachname":"Beispielbergmann","stufeId":"\(unit)"}]}
        """
        return try JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
    }

    @Test func namesAndNumbersFromFullAnswersNeverReachTheSnapshot() throws {
        let profile = try profile()
        let child = ProgramChild(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, firstName: "Maximilian", answer: nil)
        let program = Program(
            id: UUID(), title: "Waldspiel", status: .active, isAllDay: false, start: WidgetSamples.date(14, 11, 14), end: nil, dayFrom: nil, dayTo: nil,
            units: [UnitRef(id: WidgetSamples.unitId, name: "Wölfe")], children: [child],
            meetingPoint: "Pfadiheim\nTelefon 079 123 45 67 (Erika Vollname)", closingPlace: nil, closingTime: nil, bring: "Maximilian bringt Messer",
            isRegistrationOpen: nil, ownRegistration: nil
        )
        let early = WidgetSamples.date(14, 11, 9)
        let units = WidgetSnapshotBuilder.units(programs: [program], profile: profile, now: early)
        var snapshot = WidgetSnapshot(session: .signedIn, updatedAt: now)
        snapshot.units = units
        snapshot.events = WidgetSnapshotBuilder.events(programs: [program], now: early)
        let encoder = JSONEncoder()
        let json = try String(decoding: encoder.encode(snapshot), as: UTF8.self)
        for secret in ["Maximilian", "Beispielbergmann", "Erika", "Vollname", "079", "Messer", "Flinke"] { #expect(!json.contains(secret)) }
        #expect(units.first?.openAnswers == 1)
        #expect(units.first?.programs.first?.place == "Pfadiheim")
    }

    @Test func chatCountsKeepNoNamesOrTexts() throws {
        let unit = #"{"id":"\#(WidgetSamples.unitId)","name":"Wölfe","kuerzel":"W"}"#
        let json = #"""
        [{"id":"44444444-4444-4444-4444-444444444444","typ":"stufe","stufe":\#(unit),"eltern":null,"stufenleitung":[],
          "ungelesen":3,"letzteNachricht":{"text":"Geheimer Text von Frau Muster","erstelltAm":"2026-11-14T10:00:00Z","eigene":false,
          "autor":{"id":"66666666-6666-6666-6666-666666666666","name":"Frau Muster","ceviName":null}}},
         {"id":"55555555-5555-5555-5555-555555555555","typ":"stufe","stufe":\#(unit),"eltern":null,"stufenleitung":[],"ungelesen":0,"letzteNachricht":null}]
        """#
        let chats = try JSONDecoder.api.decode([ChatSummary].self, from: Data(json.utf8))
        #expect(WidgetSnapshotBuilder.chat(chats) == WidgetChat(unread: 3, chats: 1))
    }

    @Test func meetingPlaceKeepsOnlyAFirstLineWithoutNumbers() {
        #expect(WidgetSnapshotBuilder.meetingPlace("Pfadiheim Beispielwald, Eingang Nord\nTel 079 123 45 67") == "Pfadiheim Beispielwald, Eingang Nord")
        #expect(WidgetSnapshotBuilder.meetingPlace("079 123 45 67") == nil)
        #expect(WidgetSnapshotBuilder.meetingPlace("frau@example.org") == nil)
        #expect(WidgetSnapshotBuilder.meetingPlace("  ") == nil)
        #expect(WidgetSnapshotBuilder.meetingPlace(nil) == nil)
        #expect(WidgetSnapshotBuilder.meetingPlace(String(repeating: "a", count: 200))?.count == WidgetSnapshotBuilder.maxTitle)
    }

    // MARK: Stand line

    @Test func standLineFollowsTheRules() {
        let fresh = WidgetStand.make(updatedAt: now, now: now.addingTimeInterval(600), offline: false)
        #expect(fresh.text == "Stand 18:02" && !fresh.isStale)
        let stale = WidgetStand.make(updatedAt: now, now: now.addingTimeInterval(2 * 3600 + 5), offline: false)
        #expect(stale.text == "Stand vor 2 Std." && stale.isStale)
        let offline = WidgetStand.make(updatedAt: now, now: now.addingTimeInterval(60), offline: true)
        #expect(offline.text == "Ohne Netz. Stand 18:02." && offline.isOffline)
        #expect(WidgetStand.make(updatedAt: now, now: now.addingTimeInterval(49 * 3600), offline: false).text == "Stand vor 2 Tagen")
    }

    // MARK: States

    private func phase(_ kind: WidgetKind, _ snapshot: WidgetSnapshot?, privacy: Bool = false) -> WidgetPhase {
        WidgetModel.resolve(kind: kind, snapshot: snapshot, now: now, privacyRedacted: privacy).phase
    }

    @Test func statesFollowTheSnapshot() {
        #expect(phase(.nextProgram, nil) == .neverOpened)
        var wrongVersion = samples
        wrongVersion.version = 99
        #expect(phase(.chat, wrongVersion) == .neverOpened)
        #expect(phase(.calendar, .signedOut()) == .signedOut)
        var failed = samples
        failed.status = .failed
        #expect(phase(.tasks, failed) == .failed)
        for kind in WidgetKind.allCases { #expect(phase(kind, samples) == .content) }
        #expect(phase(.calendar, samples, privacy: true) == .redacted)
        var locked = samples
        locked.hidesContent = true
        #expect(phase(.campToday, locked) == .redacted)
        // The emergency widget shows no data, so there is nothing to redact.
        #expect(phase(.emergency, locked) == .content)
    }

    @Test func emptyAndNoCampStates() {
        var empty = samples
        empty.units = []
        empty.events = []
        empty.camps = []
        empty.chat = WidgetChat(unread: 0, chats: 0)
        #expect(phase(.nextProgram, empty) == .empty)
        #expect(phase(.calendar, empty) == .empty)
        #expect(phase(.chat, empty) == .empty)
        for kind in [WidgetKind.campToday, .tasks, .emergency] { #expect(phase(kind, empty) == .noCamp) }
        var quiet = samples
        quiet.camps = [WidgetCamp(id: WidgetSamples.campId, title: "L", from: now, to: now, duty: nil, important: [], todosOpen: 0, todosTotal: 0, overdueCount: 0, tasks: [], laterCount: nil, doneThisWeek: nil)]
        #expect(phase(.campToday, quiet) == .empty)
        #expect(phase(.tasks, quiet) == .empty)
    }

    @Test func offlineKeepsTheDataAndSaysSo() {
        var offline = samples
        offline.status = .offline
        let model = WidgetModel.resolve(kind: .calendar, snapshot: offline, now: now, privacyRedacted: false)
        #expect(model.phase == .content)
        #expect(model.stand?.text == "Ohne Netz. Stand 18:02.")
        #expect(WidgetModel.resolve(kind: .emergency, snapshot: offline, now: now, privacyRedacted: false).stand == nil)
    }

    // MARK: Choice (WC1, WC2)

    @Test func configuredUnitAndCampWinOverTheFirst() {
        let other = WidgetUnit(id: UUID(), name: "Adler", isChildUnit: true, programs: [WidgetProgram(id: UUID(), title: "X", start: now.addingTimeInterval(-5 * 86_400), end: nil, isAllDay: false, place: nil)], openAnswers: 0)
        var snapshot = samples
        snapshot.units.append(other)
        #expect(WidgetModel.resolve(kind: .nextProgram, snapshot: snapshot, now: now, privacyRedacted: false, unitId: other.id).unit?.name == "Adler")
        // Without a choice the unit with the earliest next program.
        #expect(WidgetModel.resolve(kind: .nextProgram, snapshot: snapshot, now: now, privacyRedacted: false).unit?.name == "Adler")
        #expect(WidgetModel.resolve(kind: .nextProgram, snapshot: snapshot, now: now, privacyRedacted: false, unitId: UUID()).unit != nil)
        let secondCamp = WidgetCamp(id: UUID(), title: "Herbstlager", from: now, to: now, duty: nil, important: [], todosOpen: 0, todosTotal: 0, overdueCount: 0, tasks: [], laterCount: nil, doneThisWeek: nil)
        snapshot.camps.append(secondCamp)
        #expect(WidgetModel.resolve(kind: .campToday, snapshot: snapshot, now: now, privacyRedacted: false, campId: secondCamp.id).camp?.title == "Herbstlager")
        #expect(WidgetModel.resolve(kind: .tasks, snapshot: snapshot, now: now, privacyRedacted: false, campId: UUID()).camp?.id == WidgetSamples.campId)
    }

    // MARK: Targets

    @Test func linksLeadToTheSameTargetsAsPushes() {
        let id = UUID()
        func target(_ url: URL) -> PushTarget? { WidgetLink.userInfo(from: url).flatMap(PushTarget.from(userInfo:)) }
        #expect(target(WidgetLink.url(typ: "programm", id: id)) == .program(id))
        #expect(target(WidgetLink.url(typ: "chats")) == .chats)
        #expect(target(WidgetLink.url(typ: "lager_heute", id: id)) == .campArea(.today, id))
        #expect(target(WidgetLink.url(typ: "lager_aufgaben", id: id)) == .campArea(.tasks, id))
        #expect(target(WidgetLink.url(typ: "lager_notfall", id: id)) == .campArea(.emergency, id))
        #expect(target(WidgetLink.url(typ: "lager_aufgabe", id: id)) == .camp(.task, id))
        #expect(target(WidgetLink.url()) == nil)
        #expect(WidgetLink.userInfo(from: URL(string: "https://example.org/open?typ=chats")!) == nil)
        #expect(target(URL(string: "cevios://open?typ=lager_heute&id=kaputt")!) == nil)
    }

    // MARK: Layout

    @Test func layoutPlanFollowsFamilyAndTypeSize() {
        #expect(WidgetLayoutPlan.calendar(.small, largeType: false).rows == 1)
        #expect(WidgetLayoutPlan.calendar(.medium, largeType: false).rows == 3)
        #expect(WidgetLayoutPlan.calendar(.large, largeType: false).rows == 5)
        #expect(WidgetLayoutPlan.calendar(.medium, largeType: true).rows == 1)
        #expect(WidgetLayoutPlan.calendar(.large, largeType: true).rows == 3)
        #expect(WidgetLayoutPlan.tasks(.medium, largeType: false).rows == 2)
        #expect(WidgetLayoutPlan.tasks(.large, largeType: true).rows == 2 && !WidgetLayoutPlan.tasks(.large, largeType: true).showsLater)
        #expect(WidgetLayoutPlan.nextProgram(.large, largeType: false).showsLater)
        #expect(!WidgetLayoutPlan.nextProgram(.large, largeType: true).showsLater)
        #expect(!WidgetLayoutPlan.nextProgram(.rectangular, largeType: false).showsPlace)
        #expect(!WidgetLayoutPlan.nextProgram(.inline, largeType: false).showsPlace)
    }

    // MARK: Formats

    @Test func datesAreSwissAndFixed() {
        let start = WidgetSamples.date(14, 11, 14)
        #expect(WidgetFormat.shortDateTime(start) == "Sa 14.11., 14:00")
        #expect(WidgetFormat.longRange(start: start, end: WidgetSamples.date(14, 11, 17), allDay: false) == "Samstag, 14. November, 14:00–17:00")
        #expect(WidgetFormat.redactedStart(start, allDay: false) == "Samstag, 14:00")
        #expect(WidgetFormat.campRange(from: WidgetSamples.date(17, 7, 0), to: WidgetSamples.date(24, 7, 0)) == "17. bis 24. Juli 2026")
        let day = WidgetFormat.campDay(WidgetSamples.date(14, 11, 12), from: WidgetSamples.date(12, 11, 0), to: WidgetSamples.date(19, 11, 0))
        #expect(day?.day == 3 && day?.of == 8)
        #expect(WidgetFormat.campDay(WidgetSamples.date(1, 11, 12), from: WidgetSamples.date(12, 11, 0), to: WidgetSamples.date(19, 11, 0)) == nil)
    }

    // MARK: Camp data

    @Test func campTasksCountOverdueAndOrderByDeadline() throws {
        let me = UUID()
        func task(_ title: String, due: Date?, status: String = "offen", done: String = "null") -> CampTask {
            let json = """
            {"id":"\(UUID())","version":1,"titel":"\(title)","ressortId":null,"teil":null,"verantwortlichPersonId":"\(me)","status":"\(status)","notiz":null,
             "frist":\(due.map { "\"\(DateFormats.calendarDayText($0))\"" } ?? "null"),"fristMeilensteinId":null,"fristVersatzTage":null,"stern":false,"laufend":false,
             "spaeterAb":null,"wiederholung":null,"reihenfolge":1,"quelle":null,"erledigtAm":\(done),"verantwortlich":null,"ressort":null,"unterstuetzung":[]}
            """
            return try! JSONDecoder.api.decode(CampTask.self, from: Data(json.utf8))
        }
        let camp = try JSONDecoder.api.decode(Camp.self, from: Data("""
        {"id":"0190a000-0000-7000-8000-000000000001","titel":"Sommerlager","von":"2026-11-12","bis":"2026-11-19","vorbereitungAb":null,"ort":null,"adresse":null,
         "status":"aktiv","farbe":null,"logoMediumId":null,"wetterOrt":{"status":"kein_ort","name":null}}
        """.utf8))
        let tasks = [
            task("Spaeter", due: WidgetSamples.date(1, 12, 0)),
            task("Zelte", due: WidgetSamples.date(10, 11, 0)),
            task("Offerte", due: WidgetSamples.date(9, 11, 0)),
            task("Fertig", due: WidgetSamples.date(1, 11, 0), status: "erledigt", done: "\"2026-11-13T10:00:00Z\""),
        ]
        let result = WidgetSnapshotBuilder.camp(camp, today: nil, week: nil, sections: [], tasks: tasks, personId: me, now: now)
        #expect(result.overdueCount == 2)
        #expect(result.tasks.map(\.title) == ["Offerte", "Zelte", "Spaeter"])
        #expect(result.tasks.map(\.isOverdue) == [true, true, false])
        #expect(result.laterCount == 1 && result.doneThisWeek == 1)
        // Without the right to read the list, the extra counts stay unknown.
        #expect(WidgetSnapshotBuilder.camp(camp, today: nil, week: nil, sections: [], tasks: nil, personId: me, now: now).laterCount == nil)
    }
}
