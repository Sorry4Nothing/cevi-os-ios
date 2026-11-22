import SwiftUI

/// L30: the emergency window. It keeps the last loaded answer in memory (`ActiveCamp.emergencySnapshot`) and shows it
/// without network; a saved offline copy follows the decision about local storage.
@MainActor @Observable
final class CampEmergencyModel: CampRosterModel {
    /// The public emergency numbers of Switzerland. They are no personal data and are always at hand.
    static let rescue: [CampEmergencyContact] = [
        CampEmergencyContact(source: .entry, id: nil, version: nil, function: String(localized: "Ambulanz"), personId: nil, name: String(localized: "Rettung"), ceviName: nil, phone: "144", order: nil),
        CampEmergencyContact(source: .entry, id: nil, version: nil, function: String(localized: "Rettungshelikopter"), personId: nil, name: "Rega", ceviName: nil, phone: "1414", order: nil),
    ]

    var emergency: CampEmergency?
    /// When the shown data was loaded, if it is older than the last try (no network).
    var loadedAt: Date?

    override init(active: ActiveCamp) {
        super.init(active: active)
        if let snapshot = active.emergencySnapshot {
            emergency = snapshot.data
            loadedAt = snapshot.loadedAt
            phase = .loaded
        }
    }

    var contacts: [CampEmergencyContact] { emergency?.contacts ?? [] }
    var address: CampEmergencyAddress? { emergency?.address }
    var infos: [CampInfo] { (emergency?.infos ?? []).sorted { ($0.order, $0.title) < ($1.order, $1.title) } }

    /// «Ohne Netz. Stand heute 18:02.» while the data is the last loaded one.
    var staleTitle: String? {
        staleSince.flatMap { _ in loadedAt }.map { String(localized: "Ohne Netz. Stand \(CampRosterText.stamp($0, now: now())).") }
    }

    func contactLabel(_ contact: CampEmergencyContact) -> String { CampRosterText.label(name: contact.name, ceviName: contact.ceviName) }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let loaded = try await client.campEmergency(campId: campId)
            emergency = loaded
            loadedAt = now()
            active.emergencySnapshot = CampEmergencySnapshot(data: loaded, loadedAt: now())
            self.loaded()
        } catch is CancellationError {
        } catch {
            // Without network the window shows what was loaded last and says so; other failures are shown as usual.
            failLoad(error, hasContent: emergency != nil)
        }
    }
}
