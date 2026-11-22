import SwiftUI

/// What the role may do in the storage screens (documents, address book, search). The defaults of the rights matrix
/// (`docs/lager.md`): the app shows only these actions, the server decides again. A missing action is a missing button.
nonisolated struct CampStorageRights: Equatable, Sendable {
    let role: CampRole?
    /// The camp is completed or archived.
    let readOnly: Bool

    private var isLead: Bool { role == .campLeader }
    private var isLeadership: Bool { role == .campLeader || role == .leader }

    /// The address book holds data of third parties: camp leadership only.
    var seesAddressBook: Bool { isLead }
    var editsAddressBook: Bool { !readOnly && isLead }

    /// The kinds the type filter of the search offers; the server still returns only what the role may see.
    var searchTypes: [CampSearchType] {
        var types: [CampSearchType] = [.task, .document, .meeting, .meetingProtocol, .noticeBoard, .dayPage, .info, .room, .trip, .group, .shift, .packingList]
        if isLeadership { types.append(.shopping) }
        if isLead { types += [.inbox, .addressBook] }
        return types
    }
}

nonisolated enum CampStorageText {
    /// Search term for the server: trimmed, at most 100 characters; `nil` if empty.
    static func term(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(100))
    }

    static func kind(_ kind: CampDocumentKind?) -> String {
        switch kind {
        case .pdf: String(localized: "PDF")
        case .image: String(localized: "Bild")
        case .word: String(localized: "Dokument")
        case .excel: String(localized: "Tabelle")
        case .link: String(localized: "Link")
        case .unknown, nil: String(localized: "Datei")
        }
    }

    static func symbol(_ kind: CampDocumentKind?) -> String {
        switch kind {
        case .pdf: "doc"
        case .image: "photo"
        case .word, .excel: "doc.text"
        case .link: "link"
        case .unknown, nil: "paperclip"
        }
    }

    static func filterName(_ filter: CampDocumentTypeFilter) -> String {
        switch filter {
        case .pdf: String(localized: "PDF")
        case .image: String(localized: "Bilder")
        case .word: String(localized: "Dokumente")
        case .excel: String(localized: "Tabellen")
        case .link: String(localized: "Links")
        case .sharepoint: String(localized: "SharePoint")
        }
    }

    /// «PDF, 240 KB»; a link or a file of unknown size has no size.
    static func subtitle(_ document: CampDocument) -> String {
        let name = kind(document.kind)
        guard document.kind != .link, let size = document.file?.size else { return name }
        let style = ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: Locale(identifier: "de_CH"))
        return "\(name), \(Int64(size).formatted(style))"
    }

    /// «neu» for a document of the last seven days.
    static func isNew(_ document: CampDocument, now: Date) -> Bool { now.timeIntervalSince(document.createdAt) < 7 * 86400 }

    /// What the screen reader reads for a document row.
    static func spoken(_ document: CampDocument, now: Date) -> String {
        var parts = [document.title, subtitle(document)]
        if isNew(document, now: now) { parts.append(String(localized: "neu")) }
        parts += document.keywords
        return parts.joined(separator: ", ")
    }

    /// `tel:` address: digits and a leading plus only; `nil` without a usable number.
    static func phoneURL(_ phone: String?) -> URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        guard digits.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:" + digits)
    }

    /// `mailto:` address; `nil` if the text is not a plain address.
    static func mailURL(_ email: String?) -> URL? {
        guard let email = CampRosterText.trimmed(email), email.contains("@"), !email.contains(where: \.isWhitespace) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }

    /// «Wird ab 12. Januar 2028 gelöscht.»; `nil` if the contact is kept.
    static func cleanUp(_ contact: CampContact) -> String? {
        guard !contact.keep, let date = contact.cleanUpFrom else { return nil }
        return String(localized: "Wird ab \(CampCommsText.day(date)) \(String(DateFormats.calendar.component(.year, from: date))) gelöscht.")
    }

    /// Heading of a group of hits: «Aufgaben».
    static func typeName(_ type: CampSearchType) -> String {
        switch type {
        case .addressBook: String(localized: "Adressbuch")
        case .task: String(localized: "Aufgaben")
        case .resolution: String(localized: "Beschlüsse")
        case .shift: String(localized: "Dienste")
        case .document: String(localized: "Dokumente")
        case .inbox: String(localized: "Eingang")
        case .shopping: String(localized: "Einkauf")
        case .trip: String(localized: "Fahrten")
        case .group: String(localized: "Gruppen")
        case .meeting: String(localized: "Hoecks")
        case .info: String(localized: "Infos")
        case .milestone: String(localized: "Meilensteine")
        case .emergency: String(localized: "Notfall")
        case .packingList: String(localized: "Packliste")
        case .noticeBoard: String(localized: "Pinnwand")
        case .meetingProtocol: String(localized: "Protokolle")
        case .portfolio: String(localized: "Ressorts")
        case .dayPage: String(localized: "Tagesseiten")
        case .participant: String(localized: "Teilnehmende")
        case .agendaItem: String(localized: "Traktanden")
        case .room: String(localized: "Zimmer")
        case .unknown: String(localized: "Weiteres")
        }
    }

    /// The screen a hit opens; `nil` where the app has no screen for the kind (the row is then not tappable).
    static func destination(_ type: CampSearchType) -> CampDestination? {
        switch type {
        case .document: .documents
        case .addressBook: .addressBook
        case .meeting, .meetingProtocol: .meetings
        case .inbox: .inbox
        case .shopping: .shopping
        case .packingList: .packing
        case .emergency: .emergency
        case .info: .infos
        case .room: .rooms
        case .trip: .trips
        case .group: .groups
        case .shift: .shifts
        case .dayPage: .dayPages
        default: nil
        }
    }
}

/// The hits of one kind, in the order of the best hit.
nonisolated struct CampSearchGroup: Identifiable, Equatable, Sendable {
    let type: CampSearchType
    let hits: [CampSearchHit]
    var id: CampSearchType { type }

    /// «Aufgaben, 2».
    var title: String { "\(CampStorageText.typeName(type)), \(hits.count)" }

    static func group(_ hits: [CampSearchHit]) -> [CampSearchGroup] {
        var order: [CampSearchType] = []
        for hit in hits where !order.contains(hit.type) { order.append(hit.type) }
        return order.map { type in CampSearchGroup(type: type, hits: hits.filter { $0.type == type }) }
    }
}

/// Reloads a list a moment after the last keystroke.
@MainActor
final class CampReloadDebouncer {
    private var task: Task<Void, Never>?

    func schedule(delay: Duration = .milliseconds(300), _ work: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await work()
        }
    }
}

/// Round 44 pt button that opens a `tel:` or `mailto:` address. The address goes to the system only, never to a log.
struct CampContactLinkButton: View {
    let symbol: String
    let label: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            Image(systemName: symbol)
                .foregroundStyle(Color.ceviOnSecondaryContainer)
                .frame(width: Size.touchTarget, height: Size.touchTarget)
                .background(Color.ceviSecondaryContainer, in: Circle())
        }
        .accessibilityLabel(Text(label))
    }
}
