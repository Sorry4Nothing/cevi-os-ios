import SwiftUI

/// K2 Raum anfragen: pick a room, a time and a purpose. The responsible team decides.
@MainActor @Observable
final class RequestRoomModel {
    enum Phase: Equatable {
        case loading
        case empty
        case ready
        case failed(text: String, isOffline: Bool)
    }

    struct Errors: Equatable {
        var room: String?
        var time: String?
        var purpose: String?

        var isEmpty: Bool { room == nil && time == nil && purpose == nil }
    }

    struct Sent: Equatable {
        let id: UUID
        let roomName: String
        let start: Date
        let end: Date
        let purpose: String
    }

    private(set) var phase: Phase = .loading
    private(set) var rooms: [Room] = []
    private(set) var errors = Errors()
    /// The room is booked at that time (`RAUM_BELEGT`), shown at the time fields.
    private(set) var bookedMessage: String?
    private(set) var sent: Sent?
    let action = ActionState()

    var roomId: UUID?
    var purpose = ""
    var date: Date
    var start: Date
    var end: Date

    init(now: Date = .now) {
        let day = DateFormats.calendar.date(byAdding: .day, value: 1, to: DateFormats.calendar.startOfDay(for: now)) ?? now
        date = day
        start = day.addingTimeInterval(16 * 3600)
        end = day.addingTimeInterval(18 * 3600)
    }

    func load(client: APIClient?) async {
        guard let client else { return }
        do {
            var page = try await client.rooms()
            for _ in 0..<10 where page.hasMore {
                guard let next = page.next else { break }
                let more = try await client.rooms(after: next)
                page = RoomPage(rooms: page.rooms + more.rooms, hasMore: more.hasMore, next: more.next)
            }
            rooms = page.rooms.filter(\.isActive)
            phase = rooms.isEmpty ? .empty : .ready
            if roomId == nil { roomId = rooms.first?.id }
        } catch is CancellationError {
        } catch let error as APIError {
            phase = .failed(text: error.displayText, isOffline: error.kind == .network)
        } catch {
            phase = .failed(text: APIError.network.displayText, isOffline: true)
        }
    }

    nonisolated static func validate(roomId: UUID?, purpose: String, start: Date, end: Date, now: Date = .now) -> Errors {
        var errors = Errors()
        if roomId == nil { errors.room = String(localized: "Wähle einen Raum.") }
        if purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.purpose = String(localized: "Gib einen Zweck ein.") }
        if end <= start {
            errors.time = String(localized: "Das Ende muss nach dem Beginn liegen.")
        } else if start < now {
            errors.time = String(localized: "Die Zeit liegt in der Vergangenheit.")
        }
        return errors
    }

    func send(client: APIClient?, now: Date = .now) async {
        let startDate = EventFormat.combine(day: date, time: start)
        let endDate = EventFormat.combine(day: date, time: end)
        errors = Self.validate(roomId: roomId, purpose: purpose, start: startDate, end: endDate, now: now)
        bookedMessage = nil
        guard errors.isEmpty, let client, let roomId, let room = rooms.first(where: { $0.id == roomId }) else { return }
        let text = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        var created: RoomRequestState?
        await action.perform(message: explain) {
            created = try await client.requestRoom(roomId: roomId, RoomRequestCreate(start: startDate, end: endDate, purpose: text))
        }
        guard let created else { return }
        sent = Sent(id: created.id, roomName: room.name, start: startDate, end: endDate, purpose: text)
        AccessibilityNotification.Announcement(String(localized: "Anfrage gesendet. Das zuständige Team bestätigt deine Anfrage.")).post()
    }

    private func explain(_ error: APIError) -> String {
        switch (error.kind, error.code) {
        case (.conflict, EventRules.roomBookedCode):
            bookedMessage = EventRules.roomError(error)
            return String(localized: "Dieser Raum ist schon belegt.")
        case (.invalidInput, EventRules.timeInPastCode):
            errors.time = String(localized: "Die Zeit liegt in der Vergangenheit.")
            return String(localized: "Prüfe deine Eingaben.")
        case (.invalidInput, EventRules.timeTooLongCode):
            errors.time = String(localized: "Die Anfrage ist zu lang. Frage eine kürzere Zeit an.")
            return String(localized: "Prüfe deine Eingaben.")
        default:
            return EventRules.roomError(error)
        }
    }

    /// «Rückgängig»: cancels the request again; the form comes back with the inputs.
    func undo(client: APIClient?) async {
        guard let sent, let client else { return }
        await action.perform(message: EventRules.roomError) { try await client.cancelRoomRequest(id: sent.id) }
        if action.error == nil { self.sent = nil }
    }
}
