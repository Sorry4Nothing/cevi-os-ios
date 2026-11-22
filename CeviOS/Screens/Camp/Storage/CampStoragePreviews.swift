#if DEBUG
import SwiftUI

/// Invented sample data for the previews of the storage screens (the day is 19 July 2027).
@MainActor
enum CampStoragePreview {
    static let now = DateFormats.calendarDay("2027-07-19") ?? Date()

    private static func uuid(_ group: Int, _ n: Int) -> UUID {
        UUID(uuidString: "0190a000-0000-7000-8000-0000000\(String(format: "%02d", group))\(String(format: "%03d", n))") ?? UUID()
    }

    private static func finish(_ model: CampRosterModel, phase: CampPhase, offline: Bool, error: String?, notice: CampRosterModel.Notice? = nil) {
        model.now = { now }
        model.phase = phase
        model.error = error
        model.notice = notice
        model.staleSince = offline ? now : nil
    }

    // MARK: L33 Documents

    private static func document(_ n: Int, _ title: String, kind: String, size: Int?, keyword: String, created: String, link: String? = "https://example.org/datei") -> CampDocument {
        let file = link.map { #"{"id":"\#(uuid(81, n))","version":1,"anzeigename":"\#(title)","link":"\#($0)","typ":null,"groesse":\#(size.map(String.init) ?? "null"),"hinzugefuegtVon":null,"hinzugefuegtAm":"2027-07-01T08:00:00Z"}"# } ?? "null"
        return CampPreview.decode("""
        {"quelle":"dokument","id":"\(uuid(80, n))","version":1,"titel":"\(title)","stichworte":["\(keyword)"],"teamSichtbar":true,"datei":\(file),
         "art":"\(kind)","sharepoint":false,"erstelltAm":"\(created)T08:00:00Z"}
        """)
    }

    static func documents(phase: CampPhase = .loaded, empty: Bool = false, offline: Bool = false, error: String? = nil, filter: CampDocumentTypeFilter? = nil, role: CampRole = .team) -> some View {
        let active = CampPreview.active(role: role, waiting: offline ? 1 : 0, offline: offline)
        let model = CampDocumentsModel(active: active)
        model.type = filter
        model.documents = empty ? [] : [document(1, "Reiseplan.pdf", kind: "pdf", size: 240_000, keyword: "Fahrt", created: "2027-07-17"),
                                       document(2, "Lagerhaus Plan.jpg", kind: "bild", size: 1_200_000, keyword: "Lagerhaus", created: "2027-06-02"),
                                       document(3, "Fahrplan SBB", kind: "link", size: nil, keyword: "Fahrt", created: "2027-06-02"),
                                       document(4, "Budget 2027.xlsx", kind: "excel", size: 48_000, keyword: "Finanzen", created: "2027-06-02")]
        finish(model, phase: phase, offline: offline, error: error)
        return NavigationStack { CampDocumentsScreen(model: model) }.environment(active)
    }

    // MARK: L34 Address book

    private static func contact(_ n: Int, _ name: String, group: String, function: String, note: String, keep: Bool = false) -> CampContact {
        CampPreview.decode("""
        {"id":"\(uuid(82, n))","version":1,"name":"\(name)","funktion":"\(function)","gruppe":"\(group)","telefon":"+41 00 000 00 00","email":"kontakt@example.org","notiz":"\(note)",
         "behalten":\(keep),"aufraeumenAb":\(keep ? "null" : "\"2028-01-12\""),"erstelltAm":"2027-06-01T08:00:00Z"}
        """)
    }

    static func addressBook(phase: CampPhase = .loaded, empty: Bool = false, error: String? = nil, role: CampRole = .campLeader, status: String = "aktiv") -> some View {
        let active = CampPreview.active(role: role, status: status)
        let model = CampAddressBookModel(active: active)
        model.contacts = empty ? [] : [contact(1, "Hauswart Lagerhaus", group: "Lagerhaus", function: "Schlüssel und Haus", note: "Erreichbar 08:00–18:00", keep: true),
                                      contact(2, "Bäckerei Beispielberg", group: "Küche", function: "Brotlieferung", note: "Bestellung bis 16:00 für den nächsten Tag")]
        finish(model, phase: role == .campLeader ? phase : .failed(state: .noAccess, text: ""), offline: false, error: error)
        return NavigationStack { CampAddressBookScreen(model: model) }.environment(active)
    }

    // MARK: L36 Search

    static func search(phase: CampPhase = .loaded, query: String = "Offerte", empty: Bool = false, error: String? = nil) -> some View {
        let active = CampPreview.active()
        let model = CampSearchModel(active: active)
        model.query = query
        func hit(_ type: String, _ n: Int, _ title: String, _ excerpt: String?) -> CampSearchHit {
            CampPreview.decode(#"{"typ":"\#(type)","id":"\#(uuid(83, n))","titel":"\#(title)","auszug":\#(excerpt.map { "\"\($0)\"" } ?? "null")}"#)
        }
        model.hits = empty ? [] : [hit("aufgabe", 1, "Offerte Lagerhaus einholen", "Logistik, überfällig"), hit("aufgabe", 2, "Offerte Car nachfragen", "Logistik, erledigt"),
                                   hit("protokoll", 3, "Hoeck 5", "Zwei Offerten liegen vor")]
        finish(model, phase: phase, offline: false, error: error)
        return NavigationStack { CampSearchScreen(model: model) }.environment(active)
    }
}

#Preview("L33 Normal") { CampStoragePreview.documents() }
#Preview("L33 Nacht") { CampStoragePreview.documents().preferredColorScheme(.dark) }
#Preview("L33 Laden") { CampStoragePreview.documents(phase: .loading) }
#Preview("L33 Leer") { CampStoragePreview.documents(empty: true) }
#Preview("L33 Fehler") { CampStoragePreview.documents(phase: .failed(state: nil, text: "x")) }
#Preview("L33 Ohne Netz") { CampStoragePreview.documents(offline: true) }
#Preview("L33 Filter Nacht") { CampStoragePreview.documents(filter: .pdf).preferredColorScheme(.dark) }
#Preview("L33 Textgrösse AX3") { CampStoragePreview.documents().dynamicTypeSize(.accessibility3) }

#Preview("L34 Normal") { CampStoragePreview.addressBook() }
#Preview("L34 Nacht") { CampStoragePreview.addressBook().preferredColorScheme(.dark) }
#Preview("L34 Laden") { CampStoragePreview.addressBook(phase: .loading) }
#Preview("L34 Leer") { CampStoragePreview.addressBook(empty: true) }
#Preview("L34 Fehler") { CampStoragePreview.addressBook(phase: .failed(state: nil, text: "x")) }
#Preview("L34 Fehler beim Speichern") { CampStoragePreview.addressBook(error: "Deine Eingabe ist noch da. Versuche es nochmals.") }
#Preview("L34 Gesperrt wegen Rolle") { CampStoragePreview.addressBook(role: .leader) }
#Preview("L34 Gesperrt Nacht") { CampStoragePreview.addressBook(role: .team).preferredColorScheme(.dark) }
#Preview("L34 Abgeschlossen") { CampStoragePreview.addressBook(status: "abgeschlossen") }
#Preview("L34 Textgrösse AX3") { CampStoragePreview.addressBook().dynamicTypeSize(.accessibility3) }

#Preview("L36 Normal") { CampStoragePreview.search() }
#Preview("L36 Nacht") { CampStoragePreview.search().preferredColorScheme(.dark) }
#Preview("L36 Laden") { CampStoragePreview.search(phase: .loading) }
#Preview("L36 Leer") { CampStoragePreview.search(query: "Oferte", empty: true) }
#Preview("L36 Ohne Eingabe") { CampStoragePreview.search(query: "") }
#Preview("L36 Fehler") { CampStoragePreview.search(phase: .failed(state: nil, text: "x")) }
#Preview("L36 Textgrösse AX3") { CampStoragePreview.search().dynamicTypeSize(.accessibility3) }
#endif
