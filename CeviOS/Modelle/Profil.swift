import Foundation

/// Rolle einer Person in einer Stufe. Stufenleitung erfüllt auch alle Rechte der Leitung derselben Stufe.
nonisolated enum RollenTyp: String, Decodable, Sendable {
    case leitung
    case stufenleitung
}

nonisolated struct Rolle: Decodable, Equatable, Sendable {
    let stufeId: UUID
    let typ: RollenTyp
}

nonisolated struct StufeKurz: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let kuerzel: String
}

nonisolated struct Kind: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let vorname: String
    let nachname: String
    let stufeId: UUID
}

/// Antwort von `GET /api/v1/ich`. Daraus leitet die App ab, was die Person sieht.
nonisolated struct Profil: Decodable, Equatable, Sendable {
    let id: UUID
    let name: String
    let ceviName: String?
    let benutzername: String?
    let mussPasswortAendern: Bool
    let datenschutzGelesenAm: Date?
    let telefon: String?
    let bildUrl: String?
    let pushChat: Bool
    let pushProgramme: Bool
    /// Fehlt für Personen ohne Stufenrolle.
    let pushAnmeldungen: Bool?
    let admin: Bool
    let zweiterFaktor: Bool
    let rollen: [Rolle]
    let stufen: [StufeKurz]
    let kinder: [Kind]

    /// Leitende und Stufenleitung haben mindestens eine Stufenrolle.
    var istLeitung: Bool { !rollen.isEmpty }

    func istStufenleitung(von stufeId: UUID) -> Bool {
        rollen.contains { $0.stufeId == stufeId && $0.typ == .stufenleitung }
    }

    func istLeitung(von stufeId: UUID) -> Bool {
        rollen.contains { $0.stufeId == stufeId }
    }

    var istStufenleitung: Bool { rollen.contains { $0.typ == .stufenleitung } }
}
