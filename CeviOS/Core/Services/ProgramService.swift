import Foundation

extension APIClient {
    /// Never cached by the server (`no-store`) and not by the client either.
    func contacts(programId: UUID) async throws -> [Contact] {
        let list: ContactList = try await load("GET", "/api/v1/programme/\(programId.uuidString.lowercased())/kontakte")
        return list.contacts
    }

    func setParticipation(programId: UUID, childId: UUID, answer: Answer) async throws {
        try await send(
            "PUT", "/api/v1/programme/\(programId.uuidString.lowercased())/teilnahmen/\(childId.uuidString.lowercased())",
            body: ["status": answer.rawValue]
        )
    }
}

/// Messages for failed answers. `reload` is true when the shown state is probably outdated.
nonisolated enum ParticipationMessages {
    static func message(for error: APIError) -> (text: String, reload: Bool) {
        switch error.kind {
        case .conflict:
            (String(localized: "Die Anmeldung ist nicht mehr möglich. Das Programm ist abgesagt oder hat schon begonnen."), true)
        case .forbidden:
            (String(localized: "Du darfst für dieses Kind nicht antworten."), true)
        case .notFound:
            (String(localized: "Dieses Programm gibt es nicht mehr oder du siehst es nicht."), true)
        default:
            (error.displayText, false)
        }
    }
}
