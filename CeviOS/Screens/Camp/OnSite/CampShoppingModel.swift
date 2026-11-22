import SwiftUI

/// L28: the shopping list by department, with «Nur was ich einkaufe», ticking and adding with suggestions.
@MainActor @Observable
final class CampShoppingModel: CampRosterModel {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let item: CampShoppingItem
        let name: String
        let amount: String?
        /// «Jonas kauft»; `nil` without a buyer.
        let buyer: String?
        var done: Bool { item.done }
    }

    struct Department: Equatable, Identifiable {
        let group: CampShoppingGroup
        let rows: [Row]
        var id: CampShoppingGroup { group }
    }

    var items: [CampShoppingItem] = []
    var onlyMine = false
    /// For «Rückgängig» after ticking.
    var lastTicked: CampShoppingItem?
    var suggestions: [CampShoppingSuggestion] = []

    var canEdit: Bool { onSite.editsShopping }

    var groups: [Department] {
        CampShoppingPage(items: items, next: nil).byGroup.map { entry in
            Department(group: entry.group, rows: entry.items.map(row))
        }
    }

    private func row(_ item: CampShoppingItem) -> Row {
        let buyerName = item.buyer.flatMap { CampRosterText.trimmed($0.ceviName) ?? CampRosterText.trimmed($0.name) }
        return Row(id: item.id, item: item, name: item.name, amount: CampOnSiteText.amount(item.amount, unit: item.unit),
                   buyer: buyerName.map { String(localized: "\($0) kauft") })
    }

    /// «Wer kauft ein: Jonas und Tim»; `nil` while nobody is named.
    var buyersLine: String? {
        var names: [String] = []
        for item in items {
            guard let name = item.buyer.flatMap({ CampRosterText.trimmed($0.ceviName) ?? CampRosterText.trimmed($0.name) }), !names.contains(name) else { continue }
            names.append(name)
        }
        return names.isEmpty ? nil : String(localized: "Wer kauft ein: \(CampRosterText.summary(names, shown: names.count))")
    }

    func setOnlyMine(_ value: Bool) async {
        onlyMine = value
        await load()
    }

    override func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            var all: [CampShoppingItem] = []
            var cursor: UUID?
            repeat {
                let page = try await client.campShopping(campId: campId, buyer: onlyMine ? .me : nil, after: cursor, limit: 100)
                all += page.items
                cursor = page.next
            } while cursor != nil && all.count < 1000
            items = all
            loaded()
        } catch is CancellationError {
        } catch {
            failLoad(error, hasContent: !items.isEmpty)
        }
    }

    /// Ticks an item off (or back) with its row version.
    func toggle(_ row: Row) async {
        guard canEdit else { return }
        await setDone(row.item, !row.item.done, undoable: true)
    }

    private func setDone(_ item: CampShoppingItem, _ done: Bool, undoable: Bool) async {
        guard let written = await writeVersioned(as: CampShoppingItem.self, { try await $0.updateCampShoppingItem(campId: $1, itemId: item.id, CampShoppingPatch(version: item.version, done: done)) }) else { return }
        if let index = items.firstIndex(where: { $0.id == written.id }) { items[index] = written }
        guard undoable else { return }
        lastTicked = item
        show(Notice(title: done ? String(localized: "\(item.name) abgehakt.") : String(localized: "\(item.name) wieder offen."), message: nil))
    }

    func undo() async {
        guard let previous = lastTicked, let current = items.first(where: { $0.id == previous.id }) else { return }
        lastTicked = nil
        notice = nil
        await setDone(current, previous.done, undoable: false)
    }

    override func dismissNotice() {
        super.dismissNotice()
        lastTicked = nil
    }

    // MARK: Adding

    /// The items whose name begins with the typed text, with their amount: «Reis, 12 kg vorhanden».
    func existing(matching text: String) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return items.filter { $0.name.localizedStandardContains(query) && $0.name.lowercased().hasPrefix(query.lowercased()) }.prefix(3).map { item in
            CampOnSiteText.amount(item.amount, unit: item.unit).map { String(localized: "\(item.name), \($0) vorhanden") } ?? String(localized: "\(item.name) vorhanden")
        }
    }

    /// Names the camp used before that begin like the typed text, without the ones the list holds already.
    func loadSuggestions(for text: String) async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let client = active.client, let campId = active.camp?.id else { suggestions = []; return }
        do {
            let found = try await client.campShoppingSuggestions(campId: campId, prefix: query, limit: 5)
            suggestions = found.filter { suggestion in !items.contains { $0.name.caseInsensitiveCompare(suggestion.name) == .orderedSame } }
        } catch is CancellationError {
        } catch {
            // Suggestions are a help only: no suggestions, no error.
            suggestions = []
        }
    }

    /// Adds an item. `true` when it was written; the sheet then closes.
    func add(name: String, amount: String, unit: String) async -> Bool {
        guard canEdit else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            error = String(localized: "Gib einen Namen ein.")
            return false
        }
        let number = amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let value = number.isEmpty ? nil : Double(number)
        if !number.isEmpty, value == nil || (value ?? 0) <= 0 {
            error = String(localized: "Die Menge muss eine Zahl über null sein.")
            return false
        }
        let body = CampShoppingCreate(name: trimmed, amount: value, unit: CampRosterText.trimmed(unit)?.lowercased())
        guard let created = await write({ try await $0.createCampShoppingItem(campId: $1, body) }) else { return false }
        items.append(created)
        suggestions = []
        show(Notice(title: String(localized: "\(created.name) hinzugefügt."), message: nil))
        return true
    }
}
