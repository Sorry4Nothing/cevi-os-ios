import SwiftUI
import UserNotifications

/// A7 Benachrichtigungen: what the app reports. The switches of the camp kinds come from
/// `GET/PUT /api/v1/ich/lager-benachrichtigungen`; the switches for chat, programs and registrations are in the profile.
@MainActor @Observable
final class NotificationsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// One switch as the design shows it. It sets one or more kinds of the server together.
    struct Group: Identifiable, Equatable {
        let id: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let kinds: [CampNotificationKind]
    }

    static let groups: [Group] = [
        Group(id: "tasks", title: "Aufgaben", detail: "Wenn dir jemand eine Aufgabe zuteilt oder sie ändert.", kinds: [.taskAssigned, .taskChanged]),
        Group(id: "mentions", title: "Erwähnungen", detail: "Wenn dich jemand mit @ erwähnt.", kinds: [.mention]),
        Group(id: "deadlines", title: "Fristen", detail: "Zwei Tage bevor eine Frist abläuft.", kinds: [.deadline]),
        Group(id: "notices", title: "Pinnwand", detail: "Wenn eine neue Mitteilung für dich erscheint.", kinds: [.importantNotice, .addressBookCleanup]),
        Group(id: "feedback", title: "Feedback", detail: "Wenn jemand auf dein Feedback antwortet.", kinds: [.feedbackReply]),
        Group(id: "swaps", title: "Diensttausch", detail: "Wenn jemand mit dir tauschen möchte oder entschieden hat.", kinds: [.shiftSwapRequest, .shiftSwapDecision]),
        Group(id: "attendance", title: "Anwesenheit", detail: "Wenn du Anwesenheiten erfassen sollst.", kinds: [.attendanceRequest]),
    ]

    private(set) var phase: Phase = .loading
    private(set) var settings: [CampNotificationKind: Bool] = [:]
    /// The system blocks notifications of this app.
    private(set) var systemBlocked = false
    let action = ActionState()

    func load(client: APIClient?) async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        systemBlocked = status == .denied
        guard let client else { return }
        do {
            let loaded = try await client.campNotificationSettings()
            settings = Dictionary(loaded.kinds.map { ($0.kind, $0.enabled) }) { a, _ in a }
            phase = .loaded
        } catch is CancellationError {
        } catch let error as APIError {
            phase = .failed(error.displayText)
        } catch {
            phase = .failed(APIError.network.displayText)
        }
    }

    /// Groups the server knows at least one kind of (the server sends all kinds it has).
    var visibleGroups: [Group] { Self.groups.filter { group in group.kinds.contains { settings[$0] != nil } } }

    func isOn(_ group: Group) -> Bool {
        group.kinds.compactMap { settings[$0] }.allSatisfy { $0 }
    }

    func set(_ group: Group, on: Bool, client: APIClient?) async {
        guard let client else { return }
        let before = settings
        let kinds = group.kinds.filter { settings[$0] != nil }
        for kind in kinds { settings[kind] = on }
        await action.perform {
            try await client.setCampNotificationSettings(kinds.map { CampNotificationSetting(kind: $0, enabled: on) })
        }
        if action.error != nil { settings = before } else { AccessibilityNotification.Announcement(String(localized: "Gespeichert")).post() }
    }
}
