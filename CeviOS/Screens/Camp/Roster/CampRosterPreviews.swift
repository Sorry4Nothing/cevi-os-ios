#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the roster screens (the camp starts on 17 July 2027).
@MainActor
enum CampRosterPreview {
    static let now = DateFormats.calendarDay("2027-07-18") ?? Date()
    private static let me = CampPreview.personId

    private static func uuid(_ group: Int, _ n: Int) -> UUID {
        UUID(uuidString: "0190a000-0000-7000-8000-00000000\(String(format: "%02d", group))\(String(format: "%02d", n))") ?? UUID()
    }

    private static func environment(_ role: CampRole, _ status: String, offline: Bool) -> ActiveCamp {
        CampPreview.active(role: role, status: status, waiting: offline ? 3 : 0, offline: offline)
    }

    private static func finish<M: CampRosterModel>(_ model: M, phase: CampPhase, offline: Bool, error: String?, notice: CampRosterModel.Notice?) {
        model.now = { now }
        model.phase = phase
        model.error = error
        model.notice = notice
        model.staleSince = offline ? now : nil
    }

    // MARK: L20 Rooms

    static func rooms(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil,
                      status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampRoomsModel(active: active)
        let team = role == .team
        func member(_ n: Int, _ name: String) -> CampRoomsModel.Member { .init(id: uuid(20, n), kind: .person, name: name) }
        model.rows = empty ? [] : [
            .init(id: uuid(21, 1), name: "Zimmer Adler", kind: .room, note: "1. Stock", places: team ? nil : 6, occupied: team ? nil : 5, overbooked: false,
                  members: [member(1, "Mara"), member(2, "Lea"), member(3, "Jonas"), member(4, "Sina"), member(5, "Tim")]),
            .init(id: uuid(21, 2), name: "Zelt 3", kind: .tent, note: team ? nil : "Wiese Nord", places: team ? nil : 4, occupied: team ? nil : 4, overbooked: false,
                  members: [member(6, "Noa"), member(7, "Lou"), member(8, "Kim"), member(9, "Ida")])]
        model.openCount = team ? 0 : 3
        finish(model, phase: phase, offline: offline, error: error, notice: notice)
        return NavigationStack { CampRoomsScreen(model: model) }.environment(active)
    }

    // MARK: L21 Trips

    private static func passengers(_ names: [String], base: Int) -> String {
        names.enumerated().map { #"{"id":"\#(uuid(30, base + $0.offset))","version":1,"personId":"\#(uuid(31, base + $0.offset))","teilnehmerId":null,"name":"\#($0.element)","stufe":null}"# }.joined(separator: ",")
    }

    static func trips(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil,
                      status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampTripsModel(active: active)
        let car: CampTrip = CampPreview.decode("""
        {"id":"\(uuid(32, 1))","version":1,"richtung":"hin","art":"auto","name":null,"fahrerPersonId":"\(uuid(31, 1))","plaetze":5,"datum":"2027-07-17","zeit":"07:30",
         "von":null,"nach":null,"treffpunkt":"Pfadiheim Beispielwald, Eingang Nord","link":null,"fahrer":{"personId":"\(uuid(31, 1))","name":"Jonas (Fuchs)"},
         "mitfahrer":[\(passengers(["Jonas", "Lea", "Tim"], base: 1))],"belegt":3,"frei":2,"ueberbelegt":false}
        """)
        let train: CampTrip = CampPreview.decode("""
        {"id":"\(uuid(32, 2))","version":1,"richtung":"hin","art":"oev","name":"ÖV-Gruppe Wölfe","fahrerPersonId":null,"plaetze":null,"datum":"2027-07-17","zeit":"07:42",
         "von":"Beispielstadt","nach":null,"treffpunkt":null,"link":"https://example.org/fahrplan","fahrer":null,
         "mitfahrer":[\(passengers(["Mara", "Sina", "Noa", "Kim", "Lou"], base: 10))],"belegt":12,"frei":null,"ueberbelegt":false}
        """)
        model.trips = empty ? [] : [car, train]
        finish(model, phase: phase, offline: offline, error: error, notice: notice)
        return NavigationStack { CampTripsScreen(model: model) }.environment(active)
    }

    // MARK: L22 Groups

    private static func group(_ n: Int, _ name: String, leaders: [String], children: Int) -> CampGroup {
        let people = leaders.enumerated().map { #"{"personId":"\#(uuid(41, n * 10 + $0.offset))","name":"\#($0.element)","ceviName":null,"rolle":"leitung"}"# }.joined(separator: ",")
        let kids = (0..<children).map { #"{"id":"\#(uuid(42, n * 20 + $0))","vorname":"Kind","nachname":"\#($0)","stufe":null,"ceviName":null}"# }.joined(separator: ",")
        return CampPreview.decode(#"{"id":"\#(uuid(40, n))","version":1,"name":"\#(name)","reihenfolge":\#(n),"personen":[\#(people)],"teilnehmer":[\#(kids)]}"#)
    }

    static func groups(phase: CampPhase = .loaded, empty: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil,
                       status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: false)
        let model = CampGroupsModel(active: active)
        model.groups = empty ? [] : [group(1, "Wölfe", leaders: ["Lea", "Tim"], children: 12), group(2, "Adler", leaders: ["Mara", "Jonas"], children: 10), group(3, "Bienli", leaders: ["Sina"], children: 8)]
        finish(model, phase: phase, offline: false, error: error, notice: notice)
        return NavigationStack { CampGroupsScreen(model: model) }.environment(active)
    }

    static func shuffle() -> some View {
        let active = environment(.campLeader, "aktiv", offline: false)
        let model = CampGroupsModel(active: active)
        model.shuffleCount = 3
        model.suggestion = CampPreview.decode("""
        {"vorschau":true,"seed":7,"geaendert":null,"gruppen":[
         {"nummer":1,"gruppeId":null,"name":"Wölfe","anzahl":11,"teilnehmer":[]},{"nummer":2,"gruppeId":null,"name":"Adler","anzahl":11,"teilnehmer":[]},
         {"nummer":3,"gruppeId":null,"name":"Bienli","anzahl":8,"teilnehmer":[]}]}
        """)
        return CampShuffleSheet(model: model) {}.environment(active)
    }

    // MARK: Shift plan, swaps

    private static let sections: [(String, String)] = [("Frühstück", "07:00–10:00"), ("Mittag", "11:00–13:30"), ("Abend", "17:00–19:30"), ("Nachtwache", "22:00–02:00"), ("Putzen", "13:30–14:30")]
    private static let dayDates = ["2027-07-17", "2027-07-18", "2027-07-19", "2027-07-20"]
    private static let people: [(String, Int)] = [("Jonas", 1), ("Sina", 2), ("Lea", 3), ("Mara", 4), ("Tim", 5)]

    private static func personUUID(_ name: String) -> UUID {
        name == "Tim" ? me : uuid(50, (people.first { $0.0 == name }?.1 ?? 9))
    }

    /// A shift on duty `d` (0 Küche Frühstück, 1 Küche Mittag, 2 Küche Abend, 3 Nachtwache, 4 Abwasch) on day `day` (0-based).
    private static func shiftJSON(_ name: String, duty d: Int, day: Int) -> String {
        """
        {"id":"\(uuid(60 + day, d * 10 + (people.first { $0.0 == name }?.1 ?? 0)))","version":1,"dienstId":"\(uuid(52, d))","lagertagId":"\(uuid(53, day))","datum":"\(dayDates[day])",
         "tagesabschnittId":"\(uuid(51, d))","personId":"\(personUUID(name))","teilnehmerId":null,"name":"\(name)","ceviName":null,"stufe":null}
        """
    }

    static func shiftID(_ name: String, duty d: Int, day: Int) -> UUID { uuid(60 + day, d * 10 + (people.first { $0.0 == name }?.1 ?? 0)) }

    static func context(empty: Bool = false) -> CampShiftContext {
        let duties = [("Küche", 2, false), ("Küche", 2, false), ("Küche", 2, false), ("Nachtwache", 1, true), ("Abwasch", 2, false)]
        let dutyJSON = duties.enumerated().map { #"{"id":"\#(uuid(52, $0.offset))","version":1,"name":"\#($0.element.0)","beschreibung":null,"mindestbesetzung":\#($0.element.1),"nacht":\#($0.element.2),"tagesabschnittId":"\#(uuid(51, $0.offset))","reihenfolge":\#($0.offset)}"# }
        let shifts = [("Jonas", 0, 0), ("Sina", 0, 0), ("Lea", 1, 0), ("Mara", 2, 0), ("Tim", 2, 0), ("Tim", 3, 0), ("Jonas", 0, 1), ("Lea", 4, 2), ("Tim", 3, 1), ("Mara", 3, 2)]
            .map { shiftJSON($0.0, duty: $0.1, day: $0.2) }
        let stats = people.map { #"{"personId":"\#(personUUID($0.0))","teilnehmerId":null,"name":"\#($0.0)","anzahl":\#($0.1 + 1),"nachtwachen":\#($0.0 == "Tim" ? 2 : 0)}"# }
        let plan: CampShiftPlan = CampPreview.decode(#"{"dienste":[\#(empty ? "" : dutyJSON.joined(separator: ","))],"schichten":[\#(empty ? "" : shifts.joined(separator: ","))],"statistik":[\#(stats.joined(separator: ","))]}"#)
        let days: [CampDay] = dayDates.enumerated().map { CampPreview.decode(#"{"id":"\#(uuid(53, $0.offset))","version":1,"datum":"\#($0.element)","label":null}"#) }
        let secs: [CampDaySection] = sections.enumerated().map { CampPreview.decode(#"{"id":"\#(uuid(51, $0.offset))","version":1,"name":"\#($0.element.0)","zeit":"\#($0.element.1)","reihenfolge":\#($0.offset)}"#) }
        return CampShiftContext(plan: plan, days: days, sections: secs)
    }

    static func shifts(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil,
                       status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampShiftsModel(active: active, personId: me)
        model.context = context(empty: empty)
        model.selectedDayId = uuid(53, 0)
        finish(model, phase: phase, offline: offline, error: error, notice: notice)
        return NavigationStack { CampShiftsScreen(model: model) }.environment(active)
    }

    static func proposal() -> some View {
        let active = environment(.campLeader, "aktiv", offline: false)
        let model = CampShiftsModel(active: active, personId: me)
        model.context = context()
        model.proposal = CampPreview.decode("""
        {"vorschau":true,"seed":3,"gekuerzt":false,"statistik":[],
         "schichten":[{"lagertagId":"\(uuid(53, 0))","datum":"2027-07-17","dienstId":"\(uuid(52, 4))","tagesabschnittId":"\(uuid(51, 4))","personId":"\(personUUID("Lea"))","teilnehmerId":null,"name":"Lea"},
                      {"lagertagId":"\(uuid(53, 0))","datum":"2027-07-17","dienstId":"\(uuid(52, 4))","tagesabschnittId":"\(uuid(51, 4))","personId":"\(personUUID("Sina"))","teilnehmerId":null,"name":"Sina"},
                      {"lagertagId":"\(uuid(53, 1))","datum":"2027-07-18","dienstId":"\(uuid(52, 1))","tagesabschnittId":"\(uuid(51, 1))","personId":"\(personUUID("Mara"))","teilnehmerId":null,"name":"Mara"}],
         "unbesetzt":[{"lagertagId":"\(uuid(53, 1))","dienstId":"\(uuid(52, 1))","fehlend":1}]}
        """)
        return CampShiftProposalSheet(model: model) {}.environment(active)
    }

    /// For the tests: the open swap request of Jonas to Lea, as JSON and decoded.
    static func swapJSON(open: Bool) -> String {
        """
        {"id":"\(uuid(70, 1))","version":1,"vonPersonId":"\(personUUID("Jonas"))","schichtId":"\(shiftID("Jonas", duty: 0, day: 1))","mitPersonId":"\(personUUID("Lea"))",
         "mitSchichtId":"\(shiftID("Lea", duty: 4, day: 2))","notiz":null,"status":"\(open ? "offen" : "angenommen")","entschiedenVon":null,"entschiedenAm":null,"erstelltAm":"2027-07-16T08:00:00Z"}
        """
    }

    static func swapSample(open: Bool) -> CampShiftSwap { CampPreview.decode(swapJSON(open: open)) }

    private static func swap(_ n: Int, from: String, shift: UUID, with: String?, withShift: UUID?, status: String, decided: String?) -> CampShiftSwap {
        CampPreview.decode("""
        {"id":"\(uuid(70, n))","version":1,"vonPersonId":"\(personUUID(from))","schichtId":"\(shift)","mitPersonId":\(with.map { "\"\(personUUID($0))\"" } ?? "null"),
         "mitSchichtId":\(withShift.map { "\"\($0)\"" } ?? "null"),"notiz":null,"status":"\(status)","entschiedenVon":null,"entschiedenAm":\(decided.map { "\"\($0)\"" } ?? "null"),
         "erstelltAm":"2027-07-16T08:00:00Z"}
        """)
    }

    static func swaps(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, notice: CampRosterModel.Notice? = nil,
                      status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampSwapsModel(active: active, personId: me)
        model.context = context()
        model.swaps = empty ? [] : [
            swap(1, from: "Jonas", shift: shiftID("Jonas", duty: 0, day: 1), with: "Lea", withShift: shiftID("Lea", duty: 4, day: 2), status: "offen", decided: nil),
            swap(2, from: "Tim", shift: shiftID("Tim", duty: 3, day: 1), with: "Mara", withShift: shiftID("Mara", duty: 3, day: 2), status: "angenommen", decided: "2027-07-17T19:10:00Z")]
        finish(model, phase: phase, offline: offline, error: error, notice: notice)
        return NavigationStack { CampSwapsScreen(model: model) }.environment(active)
    }

    // MARK: L25 Counting

    static func count(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, notice: CampRosterModel.Notice? = nil, undo: Bool = false,
                      status: String = "aktiv", role: CampRole = .campLeader) -> some View {
        let active = environment(role, status, offline: offline)
        let model = CampCountModel(active: active)
        func row(_ n: Int, _ label: String, _ checked: Bool) -> CampCountModel.Row { .init(id: uuid(80, n), participantId: nil, personId: uuid(81, n), label: label, checked: checked) }
        model.rows = empty ? [] : [row(1, "Mara (Luchs)", true), row(2, "Jonas (Fuchs)", true), row(3, "Lea (Biber)", true), row(4, "Tim (Spatz)", false)]
        model.present = empty ? 0 : 18
        model.total = empty ? 0 : 22
        model.groups = [group(1, "Wölfe", leaders: [], children: 0), group(2, "Adler", leaders: [], children: 0)]
        model.scope = .team
        if undo { model.snapshot = .init(participantIds: [], personIds: [uuid(81, 1)]) }
        finish(model, phase: phase, offline: offline, error: nil, notice: notice)
        return NavigationStack { CampCountScreen(model: model) }.environment(active)
    }
}
#endif
