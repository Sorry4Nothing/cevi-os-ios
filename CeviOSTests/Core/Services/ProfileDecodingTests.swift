import Foundation
import Testing
@testable import CeviOS

/// `GET /api/v1/ich` after the backend change of 25.11.: `admin` is gone, the department lead is `abteilungsleitung`.
struct ProfileDecodingTests {
    private func profile(extra: String, lead: Bool = false) throws -> Profile {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Eva Beispiel","ceviName":null,"geschlecht":"w","benutzername":"e.beispiel",
         "mussPasswortAendern":false,"datenschutzGelesenAm":null,"telefon":null,"bildUrl":null,"pushChat":true,"pushProgramme":true,
         "zweiterFaktor":false,"rollen":[],"stufen":[],"kinder":[]\(extra)}
        """
        return try JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
    }

    @Test func readsTheNewFields() throws {
        let p = try profile(extra: """
        ,"abteilungsleitung":true,"entwickler":false,"clientArt":"app_nachgewiesen",
         "rechte":[{"recht":"kinder.verwalten","geltung":"eigene"}]
        """)
        #expect(p.isDepartmentLead && !p.isDeveloper && p.clientKind == .verifiedApp)
        #expect(p.rights == [ProfileRight(name: "kinder.verwalten", scope: "eigene")])
        #expect(p.isAdminOnly)
        #expect(p.participant == nil)
    }

    @Test func missingNewFieldsAndUnknownClientKindDoNotBreakTheSignIn() throws {
        let bare = try profile(extra: "")
        #expect(!bare.isDepartmentLead && bare.rights.isEmpty && bare.clientKind == .unknown)
        let future = try profile(extra: #","clientArt":"quantum""#)
        #expect(future.clientKind == .unknown)
    }

    @Test func participantAccountIsRead() throws {
        let p = try profile(extra: """
        ,"abteilungsleitung":false,"entwickler":false,"clientArt":"web","rechte":[],
         "teilnehmer":{"kindId":"22222222-2222-2222-2222-222222222222","stufeId":"33333333-3333-3333-3333-333333333333","aktiv":true,"chat":"lesen"}
        """)
        #expect(p.participant?.chat == "lesen" && p.participant?.isActive == true)
        #expect(!p.isAdminOnly)
    }
}
