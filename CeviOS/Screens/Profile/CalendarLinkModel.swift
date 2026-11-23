import SwiftUI

/// A6 «Mein Kalender-Link»: status, create or replace, revoke. The address exists only in `newLink` until the sheet is
/// closed; it is never stored, logged or put into a label.
@MainActor @Observable
final class CalendarLinkModel {
    enum Phase: Equatable {
        case loading
        case loaded(CalendarLinkStatus)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    /// The freshly created link for the sheet with the share button. `nil` after closing.
    var newLink: CalendarLinkNew?
    let action = ActionState()

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            phase = .loaded(try await client.calendarLinkStatus())
        } catch is CancellationError {
        } catch let error as APIError {
            if case .loaded = phase { return }
            phase = .failed(error.displayText)
        } catch {
            phase = .failed(APIError.network.displayText)
        }
    }

    /// Creates the first link or replaces the old one (the old one stops working).
    func create(client: APIClient?) async {
        guard let client else { return }
        var created: CalendarLinkNew?
        await action.perform { created = try await client.createCalendarLink() }
        guard let created else { return }
        newLink = created
        await load(client: client)
    }

    func revoke(client: APIClient?) async {
        guard let client else { return }
        await action.perform { try await client.revokeCalendarLink() }
        if action.error == nil {
            AccessibilityNotification.Announcement(String(localized: "Link widerrufen")).post()
            await load(client: client)
        }
    }
}
