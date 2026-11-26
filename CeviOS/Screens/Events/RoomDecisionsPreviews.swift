#if DEBUG
import SwiftUI

/// Invented sample data for the previews of K5.
@MainActor
enum RoomDecisionsPreview {
    private static func request(_ n: Int, room: String, by: String, purpose: String) -> RoomRequest {
        let json = """
        {"id":"0190a000-0000-7000-8000-0000000a00\(String(format: "%02d", n))","raumId":"0190a000-0000-7000-8000-0000000b0001","raumName":"\(room)",
         "beginn":"2027-03-06T13:00:00Z","ende":"2027-03-06T16:00:00Z","zweck":"\(purpose)","status":"angefragt","begruendung":null,
         "entschiedenAm":null,"erstelltAm":"2027-03-01T08:00:00Z","vonName":"\(by)"}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder.api.decode(RoomRequest.self, from: Data(json.utf8))
    }

    static let requests = [request(1, room: "Pfadiheim gross", by: "Lea Beispiel", purpose: "Leitungssitzung"),
                           request(2, room: "Gruppenraum", by: "Jan Muster", purpose: "Bastelnachmittag der Wölfe")]

    static func screen(_ model: RoomDecisionsModel) -> some View {
        NavigationStack { RoomDecisionsView(model: model) }.environment(AppState())
    }
}

#Preview("K5 Normal") { RoomDecisionsPreview.screen(RoomDecisionsModel(phase: .loaded, requests: RoomDecisionsPreview.requests)) }
#Preview("K5 Nacht") { RoomDecisionsPreview.screen(RoomDecisionsModel(phase: .loaded, requests: RoomDecisionsPreview.requests)).preferredColorScheme(.dark) }
#Preview("K5 Laden") { RoomDecisionsPreview.screen(RoomDecisionsModel(phase: .loading)) }
#Preview("K5 Leer") { RoomDecisionsPreview.screen(RoomDecisionsModel(phase: .loaded)) }
#Preview("K5 Fehler") { RoomDecisionsPreview.screen(RoomDecisionsModel(phase: .failed(text: "Etwas ist schiefgegangen.", isOffline: false))) }
#Preview("K5 Ohne Netz") { RoomDecisionsPreview.screen(RoomDecisionsModel(phase: .failed(text: "Keine Verbindung zum Server.", isOffline: true))) }
#Preview("K5 Raum belegt und Netzfehler") {
    let list = RoomDecisionsPreview.requests
    return RoomDecisionsPreview.screen(RoomDecisionsModel(
        phase: .loaded, requests: list,
        rowErrors: [list[0].id: "Der Raum ist zu dieser Zeit schon gebucht. Du kannst die Anfrage nur ablehnen.", list[1].id: "Keine Verbindung zum Server. Bitte später nochmals versuchen."],
        bookedIds: [list[0].id], retryable: [list[1].id: .accept]))
}
#endif
