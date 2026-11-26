#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the camp check.
@MainActor
enum CampCheckPreview {
    private static let now = DateFormats.calendarDay("2027-07-05") ?? Date()

    private static func id(_ n: Int) -> String { "0190a000-0000-7000-8000-0000000900\(String(format: "%02d", n))" }

    static func screen(phase: CampPhase = .loaded, state: CampCheckState = .open, empty: Bool = false, offline: Bool = false,
                       error: String? = nil, retry: Bool = false, role: CampRole = .campLeader, status: String = "aktiv") -> some View {
        let active = CampPreview.active(role: role, status: status, waiting: 0, offline: offline)
        let model = CampCheckModel(active: active)
        let notes = state == .ready ? "" : """
        {"code":"AUFGABEN_UEBERFAELLIG","schwere":"offen","text":"2 Aufgaben sind überfällig.","anzahl":2,"beispiele":[
          {"id":"\(id(1))","titel":"Offerte Lagerhaus einholen","datum":"2027-07-01"},{"id":"\(id(2))","titel":"Zelte prüfen","datum":"2027-07-03"}]},
        {"code":"MEILENSTEIN_NAH","schwere":"hinweis","text":"Ein Meilenstein ist in einer Woche.","anzahl":1,"beispiele":[
          {"id":"\(id(3))","titel":"Anmeldeschluss","datum":"2027-07-12","offeneAufgaben":3}]}
        """
        model.check = CampPreview.decode("""
        {"stand":"\(state.rawValue)","datum":"2027-07-05","pruefer":[
          {"id":"aufgaben","titel":"Aufgaben","stand":"\(state.rawValue)","hinweise":[\(notes)]},
          {"id":"packliste","titel":"Packliste","stand":"bereit","hinweise":[]}]}
        """)
        model.points = empty ? [] : [
            CampPreview.decode(#"{"id":"\#(id(10))","version":1,"titel":"Elternbrief verschicken","erledigt":true,"reihenfolge":0}"#),
            CampPreview.decode(#"{"id":"\#(id(11))","version":1,"titel":"Erste-Hilfe-Kurs der Leitung prüfen","erledigt":false,"reihenfolge":1}"#),
        ]
        model.now = { now }
        model.phase = phase
        model.error = error
        model.staleSince = offline ? now : nil
        if retry { model.simulateFailure() }
        return NavigationStack { CampCheckScreen(model: model) }.environment(active)
    }
}

#Preview("L1a Offen") { CampCheckPreview.screen() }
#Preview("L1a Offen Nacht") { CampCheckPreview.screen().preferredColorScheme(.dark) }
#Preview("L1a Bereit") { CampCheckPreview.screen(state: .ready) }
#Preview("L1a Laden") { CampCheckPreview.screen(phase: .loading) }
#Preview("L1a Leer") { CampCheckPreview.screen(state: .ready, empty: true) }
#Preview("L1a Fehler") { CampCheckPreview.screen(phase: .failed(state: nil, text: "x")) }
#Preview("L1a Ohne Netz") { CampCheckPreview.screen(offline: true) }
#Preview("L1a Schreiben gescheitert") { CampCheckPreview.screen(error: "Keine Verbindung. Bitte später nochmals versuchen.", retry: true) }
#Preview("L1a Nur lesen") { CampCheckPreview.screen(role: .readOnly) }
#Preview("L1a Abgeschlossen") { CampCheckPreview.screen(status: "abgeschlossen") }
#endif
