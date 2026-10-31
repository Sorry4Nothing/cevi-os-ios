import Foundation
import Testing
@testable import CeviOS

nonisolated enum Beispiele {
    static func profil(
        mussPasswortAendern: Bool = false,
        datenschutz: String? = "2026-10-01T10:00:00.000Z",
        rollen: String = "[]"
    ) throws -> Profil {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Test Person","ceviName":null,"benutzername":"test.person",
         "mussPasswortAendern":\(mussPasswortAendern),"datenschutzGelesenAm":\(datenschutz.map { "\"\($0)\"" } ?? "null"),
         "telefon":null,"bildUrl":null,"pushChat":true,"pushProgramme":true,"admin":false,"zweiterFaktor":false,
         "rollen":\(rollen),"stufen":[],"kinder":[]}
        """
        return try JSONDecoder.api.decode(Profil.self, from: Data(json.utf8))
    }
}

struct PhaseTests {
    @Test func offenerPasswortwechselGehtVorDatenschutz() throws {
        let profil = try Beispiele.profil(mussPasswortAendern: true, datenschutz: nil)
        #expect(AppZustand.phase(fuer: profil) == .passwortAendern(profil))
    }

    @Test func ohneKenntnisnahmeKommtDerDatenschutz() throws {
        let profil = try Beispiele.profil(datenschutz: nil)
        #expect(AppZustand.phase(fuer: profil) == .datenschutz(profil))
    }

    @Test func sonstIstDieAppBereit() throws {
        let profil = try Beispiele.profil()
        #expect(AppZustand.phase(fuer: profil) == .bereit(profil))
    }
}

struct ProfilTests {
    @Test func rollenMachenAusEinerPersonEineLeitung() throws {
        let stufe = "22222222-2222-2222-2222-222222222222"
        let profil = try Beispiele.profil(rollen: #"[{"stufeId":"\#(stufe)","typ":"stufenleitung"}]"#)
        let id = try #require(UUID(uuidString: stufe))
        #expect(profil.istLeitung)
        #expect(profil.istStufenleitung(von: id))
        #expect(profil.istLeitung(von: id))
        #expect(!profil.istLeitung(von: UUID()))
    }

    @Test func ohneRollenIstEsEinElternteil() throws {
        #expect(try !Beispiele.profil().istLeitung)
    }
}

struct SperreTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func nachFuenfMinutenIstDieSperreFaellig() {
        #expect(AppSperre.sperreFaellig(hintergrundSeit: start, jetzt: start.addingTimeInterval(300)))
        #expect(AppSperre.sperreFaellig(hintergrundSeit: start, jetzt: start.addingTimeInterval(3600)))
    }

    @Test func davorNicht() {
        #expect(!AppSperre.sperreFaellig(hintergrundSeit: start, jetzt: start.addingTimeInterval(299)))
        #expect(!AppSperre.sperreFaellig(hintergrundSeit: nil, jetzt: start))
    }

    @MainActor @Test func kaltstartIstGesperrtUndSzenenwechselSperrtNachWartezeit() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let sperre = AppSperre(defaults: defaults)
        #expect(sperre.istGesperrt)
        sperre.szenenphase(.background, jetzt: start)
        sperre.szenenphase(.active, jetzt: start.addingTimeInterval(10))
        #expect(sperre.istGesperrt) // Kaltstart: erst entsperren() hebt die Sperre auf.
    }

    @MainActor @Test func elternKoennenDieSperreAbschaltenLeitendeNicht() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let sperre = AppSperre(defaults: defaults)
        let eltern = try Beispiele.profil()
        let leitung = try Beispiele.profil(rollen: #"[{"stufeId":"22222222-2222-2222-2222-222222222222","typ":"leitung"}]"#)
        #expect(sperre.elternSperreAktiv)
        #expect(sperre.istErforderlich(fuer: eltern))
        sperre.elternSperreAktiv = false
        #expect(!sperre.istErforderlich(fuer: eltern))
        #expect(sperre.istErforderlich(fuer: leitung))
    }
}

struct AuthDienstTests {
    @Test func zweiterFaktorAufforderungWirdErkannt() {
        let daten = Data(#"{"twoFactorRedirect":true,"twoFactorMethods":["totp"]}"#.utf8)
        #expect(APIClient.anmeldeErgebnis(aus: daten) == .zweiterFaktor)
    }

    @Test func normaleAnmeldungWirdErkannt() {
        let daten = Data(#"{"redirect":false,"token":"x","user":{"id":"1","name":"A"}}"#.utf8)
        #expect(APIClient.anmeldeErgebnis(aus: daten) == .angemeldet)
    }

    @Test func sitzungNullBedeutetKeineSitzung() {
        #expect(!APIClient.sitzungVorhanden(in: Data("null".utf8)))
        #expect(!APIClient.sitzungVorhanden(in: Data(" null\n".utf8)))
        #expect(APIClient.sitzungVorhanden(in: Data(#"{"session":{},"user":{}}"#.utf8)))
    }

    @Test func passwortFehlerBekommenDeutscheTexte() {
        let kurz = APIFehler(art: .ungueltigeEingabe, status: 400, code: "PASSWORD_TOO_SHORT", meldung: "Password too short")
        #expect(AuthMeldungen.passwortAendern(kurz) == "Das neue Passwort muss mindestens 12 Zeichen haben.")
        let gleich = APIFehler(art: .ungueltigeEingabe, status: 400, code: "PASSWORT_UNVERAENDERT", meldung: "Das neue Passwort muss sich vom bisherigen unterscheiden.")
        #expect(AuthMeldungen.passwortAendern(gleich) == "Das neue Passwort muss sich vom bisherigen unterscheiden.")
    }

    @Test func zweiterFaktorFehlerUnterscheidenFalschenCodeUndAbgelaufenenSchritt() {
        let falsch = APIFehler(art: .nichtAngemeldet, status: 401, code: "INVALID_CODE", meldung: "Invalid code")
        #expect(AuthMeldungen.zweiterFaktor(falsch).neuAnmelden == false)
        let zuViele = APIFehler(art: .ungueltigeEingabe, status: 400, code: "TOO_MANY_ATTEMPTS_REQUEST_NEW_CODE", meldung: "x")
        #expect(AuthMeldungen.zweiterFaktor(zuViele).neuAnmelden)
    }

    @Test func serverSeitenBekommenDieBasisURL() {
        let basis = URL(string: "https://api.example.org")
        #expect(ServerSeite.datenschutz.url(basis: basis)?.absoluteString == "https://api.example.org/datenschutz")
        #expect(ServerSeite.support.url(basis: nil) == nil)
    }
}
