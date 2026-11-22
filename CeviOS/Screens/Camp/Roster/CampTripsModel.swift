import SwiftUI

nonisolated enum CampTripText {
    /// «Auto von Jonas (Fuchs)» or the name of the trip; without driver «Auto», public transport «ÖV-Gruppe».
    static func title(_ trip: CampTrip) -> String {
        if let name = CampRosterText.trimmed(trip.name) { return name }
        switch trip.kind {
        case .car: return CampRosterText.trimmed(trip.driver?.name).map { String(localized: "Auto von \($0)") } ?? String(localized: "Auto")
        case .publicTransport: return String(localized: "ÖV-Gruppe")
        }
    }

    /// «Abfahrt Samstag, 07:30»; for public transport «Zug ab Beispielstadt, 07:42».
    static func departure(_ trip: CampTrip) -> String? {
        let day = trip.date.map { CampRosterText.weekday($0) }
        let when = [day, CampRosterText.trimmed(trip.time)].compactMap { $0 }.joined(separator: ", ")
        if trip.kind == .publicTransport, let from = CampRosterText.trimmed(trip.from) {
            return when.isEmpty ? String(localized: "Zug ab \(from)") : String(localized: "Zug ab \(from), \(when)")
        }
        return when.isEmpty ? nil : String(localized: "Abfahrt \(when)")
    }

    /// «3 von 5» with places, «12 Personen» without.
    static func count(_ trip: CampTrip) -> String {
        trip.places.map { CampRosterText.occupancy(trip.occupied, of: $0) } ?? CampRosterText.people(trip.occupied)
    }

    /// Only a plain `https` link opens (the data layer validates it again on the server).
    static func link(_ trip: CampTrip) -> URL? {
        guard let text = trip.link, let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// L21: the trips there and back with their passengers.
@MainActor @Observable
final class CampTripsModel: CampRosterModel {
    var trips: [CampTrip] = []
    var direction: CampTripDirection = .outbound

    var visible: [CampTrip] { trips.filter { $0.direction == direction } }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampTrip] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campTrips(campId: campId, after: cursor, limit: 100)
                all += page.trips
                cursor = page.next
            } while cursor != nil && all.count < 1000
            trips = all
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !trips.isEmpty)
        }
    }

    /// The people without a trip in the direction of the open list.
    func loadPeopleWithoutTrip() async {
        let direction = direction
        await loadChoices { client, campId in
            var result: [CampPersonChoice] = []
            var cursor: String?
            repeat {
                let page = try await client.campPeopleWithoutTrip(campId: campId, direction: direction, after: cursor, limit: 100)
                result += page.people.compactMap { person in
                    guard let id = person.participantId ?? person.personId else { return nil }
                    return CampPersonChoice(id: id, isParticipant: person.participantId != nil, label: CampRosterText.trimmed(person.name) ?? CampRosterText.unknownPerson, detail: person.level)
                }
                cursor = page.next
            } while cursor != nil && result.count < 1000
            return result
        }
    }

    func board(_ people: [CampPersonChoice], on tripId: UUID) async {
        guard rights.placesPeople, !people.isEmpty else { return }
        var added = 0
        for person in people {
            let body = CampTripPassengerCreate(personId: person.isParticipant ? nil : person.id, participantId: person.isParticipant ? person.id : nil)
            guard await write({ try await $0.addCampPassenger(campId: $1, tripId: tripId, body) }) != nil else { break }
            added += 1
        }
        if added > 0 {
            let title = added == 1 ? String(localized: "\(people[0].label) fährt mit.") : String(localized: "\(added) Personen eingeteilt.")
            show(Notice(title: title, message: nil))
        }
        await load()
    }

    func remove(_ passenger: CampTripPassenger, from tripId: UUID) async {
        guard rights.placesPeople else { return }
        guard await writeVersioned(as: CampTrip.self, { try await $0.removeCampPassenger(campId: $1, tripId: tripId, passengerId: passenger.id, version: passenger.version) }) != nil else { return }
        show(Notice(title: String(localized: "\(passenger.name) fährt nicht mehr mit.")))
        await load()
    }
}
