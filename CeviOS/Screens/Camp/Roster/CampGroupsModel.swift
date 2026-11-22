import SwiftUI

/// L22: the program groups, and «Automatisch mischen» as a suggestion that the person confirms.
@MainActor @Observable
final class CampGroupsModel: CampRosterModel {
    static let countRange = 2...20

    var groups: [CampGroup] = []
    var withoutGroup = 0
    /// How many groups the mix makes.
    var shuffleCount = 3
    /// The suggestion shown for confirmation (nothing is written yet).
    var suggestion: CampGroupShuffle?
    var isSuggesting = false

    /// Mixing changes every group: for the camp leadership only.
    var canShuffle: Bool { rights.placesPeople }

    static func leaders(_ group: CampGroup) -> [String] {
        group.people.filter { $0.role == .leader }.map { CampRosterText.label(name: $0.name, ceviName: nil) }
    }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            let list = try await client.campGroups(campId: campId)
            groups = list.groups.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            withoutGroup = list.withoutGroup
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !groups.isEmpty)
        }
    }

    func beginShuffle() {
        suggestion = nil
        shuffleCount = min(max(groups.count, Self.countRange.lowerBound), Self.countRange.upperBound)
    }

    /// Step 1: asks the server for a mix. Each call without a seed gives a new one («Neu mischen»).
    func suggest() async {
        guard canShuffle else { return }
        let count = min(max(shuffleCount, Self.countRange.lowerBound), Self.countRange.upperBound)
        isSuggesting = true
        defer { isSuggesting = false }
        suggestion = await write({ try await $0.suggestCampGroupShuffle(campId: $1, count: count) })
    }

    /// Step 2: writes the mix the person saw. Returns true if it was written.
    func confirm() async -> Bool {
        guard canShuffle, let suggestion else { return false }
        guard let result = await write({ try await $0.confirmCampGroupShuffle(campId: $1, suggestion) }) else { return false }
        self.suggestion = nil
        let moved = result.changed ?? 0
        show(Notice(title: String(localized: "Gruppen gemischt."), message: String(localized: "\(CampRosterText.children(moved)) neu verteilt.")))
        await load()
        return true
    }

    func cancelShuffle() { suggestion = nil }
}
