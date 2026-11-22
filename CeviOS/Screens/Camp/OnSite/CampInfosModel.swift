import SwiftUI

/// L32: the info sections of the camp (house, rules, daily routine), in the order of the camp leadership.
@MainActor @Observable
final class CampInfosModel: CampRosterModel {
    var infos: [CampInfo] = []
    /// «Sortieren»: the arrows to move a section are shown.
    var isReordering = false

    var canReorder: Bool { onSite.reordersInfos }
    /// The others are told that some sections are for the camp leadership.
    var showsRestrictedHint: Bool { !onSite.seesAllInfos }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampInfo] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campInfos(campId: campId, after: cursor, limit: 100)
                all += page.sections
                cursor = page.next
            } while cursor != nil && all.count < 500
            infos = all.sorted { ($0.order, $0.title) < ($1.order, $1.title) }
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !infos.isEmpty)
        }
    }

    func canMove(_ info: CampInfo, by offset: Int) -> Bool {
        guard canReorder, let index = infos.firstIndex(where: { $0.id == info.id }) else { return false }
        return infos.indices.contains(index + offset)
    }

    /// The visible alternative to dragging: «Nach oben» and «Nach unten».
    func move(_ info: CampInfo, by offset: Int) async {
        guard canMove(info, by: offset), let index = infos.firstIndex(where: { $0.id == info.id }) else { return }
        let before = infos
        infos.swapAt(index, index + offset)
        let order = infos.map { CampVersionRef(id: $0.id, version: $0.version) }
        guard await writeVersioned(as: CampInfo.self, { try await $0.reorderCampInfos(campId: $1, order) }) != nil else {
            infos = before
            return
        }
        show(Notice(title: String(localized: "Reihenfolge gespeichert."), message: nil))
        await load()
    }
}
