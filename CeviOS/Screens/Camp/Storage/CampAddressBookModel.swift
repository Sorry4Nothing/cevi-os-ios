import SwiftUI

/// L34: the address book of the camp, for the camp leadership only. Names, phone numbers, addresses and notes are data of
/// third parties: never in widgets, logs or crash reports, and never cached.
@MainActor @Observable
final class CampAddressBookModel: CampRosterModel {
    var contacts: [CampContact] = []
    var query = ""
    @ObservationIgnored let debouncer = CampReloadDebouncer()

    var storage: CampStorageRights { CampStorageRights(role: active.role, readOnly: active.isReadOnly) }
    /// The role may not read the address book, or the server said so (403): the screen shows «Kein Zugriff».
    var isLocked: Bool {
        if case .failed(.noAccess?, _) = phase { return true }
        return !storage.seesAddressBook
    }

    override func load() async {
        guard storage.seesAddressBook else {
            phase = .failed(state: .noAccess, text: "")
            return
        }
        guard let client = active.client, let campId = active.camp?.id else { return }
        let search = CampStorageText.term(query)
        do {
            var all: [CampContact] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campContacts(campId: campId, search: search, after: cursor, limit: 100)
                all += page.contacts
                cursor = page.next
            } while cursor != nil && all.count < 500
            contacts = all
            loaded()
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            failLoad(error, hasContent: !contacts.isEmpty)
        }
    }

    func reloadSoon() { debouncer.schedule { [weak self] in await self?.load() } }

    /// «Fürs nächste Lager behalten».
    func setKeep(_ contact: CampContact, _ keep: Bool) async {
        guard storage.editsAddressBook else { return }
        guard let written = await writeVersioned(as: CampContact.self, { client, campId in
            try await client.updateCampContact(campId: campId, contactId: contact.id, CampContactPatch(version: contact.version, keep: keep))
        }) else { return }
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[index] = written }
    }

    /// «Kontakt sichern». `false` if the input is not enough or the server refused it; the message line then says why.
    func add(name: String, phone: String, email: String) async -> Bool {
        guard storage.editsAddressBook else { return false }
        guard let name = CampRosterText.trimmed(name) else {
            error = String(localized: "Gib einen Namen ein.")
            return false
        }
        let body = CampContactCreate(name: name, phone: CampRosterText.trimmed(phone), email: CampRosterText.trimmed(email))
        guard let created = await write({ client, campId in try await client.createCampContact(campId: campId, body) }) else { return false }
        contacts = (contacts + [created]).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        show(Notice(title: String(localized: "Kontakt gesichert."), message: nil))
        return true
    }
}
