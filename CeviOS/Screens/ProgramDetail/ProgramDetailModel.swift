import SwiftUI

@MainActor @Observable
final class ProgramDetailModel {
    private(set) var program: Program?
    private(set) var contacts: [Contact] = []
    private(set) var loadError: String?
    /// Children whose answer is being saved. Blocks double taps.
    private(set) var saving: Set<UUID> = []
    private(set) var savingOwn = false
    var answerError: String?

    func load(programId: UUID, client: APIClient?) async {
        guard let client else { return }
        do {
            program = try await client.program(id: programId)
            loadError = nil
        } catch is CancellationError {
            return
        } catch let error as APIError {
            loadError = error.displayText
            return
        } catch {
            loadError = APIError.network.displayText
            return
        }
        // Contacts are not critical: without them the detail still works.
        contacts = (try? await client.contacts(programId: programId)) ?? []
    }

    /// Silent refresh while the detail is open: no loading state, errors keep what is shown.
    func refresh(programId: UUID, client: APIClient?) async {
        guard let client, let fresh = try? await client.program(id: programId) else { return }
        program = fresh
        if let contacts = try? await client.contacts(programId: programId) { self.contacts = contacts }
    }

    func setOwnRegistration(_ answer: Answer, programId: UUID, client: APIClient?) async {
        guard let client, !savingOwn else { return }
        savingOwn = true
        answerError = nil
        defer { savingOwn = false }
        do {
            try await client.setOwnRegistration(programId: programId, answer: answer)
            // The selected state changes on the focused button without a new element to focus; say that it worked.
            AccessibilityNotification.Announcement(String(localized: "Gespeichert")).post()
            await load(programId: programId, client: client)
        } catch let error as APIError {
            let message = LeadershipMessages.message(for: error)
            answerError = message.text
            if message.reload { await load(programId: programId, client: client) }
        } catch {
            answerError = APIError.network.displayText
        }
    }

    func answer(_ answer: Answer, for child: ProgramChild, programId: UUID, client: APIClient?) async {
        guard let client, !saving.contains(child.id) else { return }
        saving.insert(child.id)
        answerError = nil
        defer { saving.remove(child.id) }
        do {
            try await client.setParticipation(programId: programId, childId: child.id, answer: answer)
            // The selected state changes on the focused button without a new element to focus; say that it worked.
            AccessibilityNotification.Announcement(String(localized: "Gespeichert")).post()
            await load(programId: programId, client: client)
        } catch let error as APIError {
            let message = ParticipationMessages.message(for: error)
            answerError = message.text
            if message.reload { await load(programId: programId, client: client) }
        } catch {
            answerError = APIError.network.displayText
        }
    }
}
