import AppIntents
import WidgetKit

/// Both configurations read the choices from the snapshot. The system draws the list (title «Stufe wählen» / «Lager wählen»).
protocol SelectionIntent {
    var unitId: UUID? { get }
    var campId: UUID? { get }
}

struct UnitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stufe"
    static let defaultQuery = UnitQuery()

    let id: String
    let name: String
    let isChildUnit: Bool

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = isChildUnit ? "Für dein Kind in der Stufe \(name)" : "Für deine Stufe \(name)"
        return DisplayRepresentation(title: "\(name)", subtitle: subtitle)
    }
}

struct UnitQuery: EntityQuery {
    private var units: [UnitEntity] {
        (WidgetStore.shared.read()?.units ?? []).map { UnitEntity(id: $0.id.uuidString, name: $0.name, isChildUnit: $0.isChildUnit) }
    }

    func entities(for identifiers: [String]) async throws -> [UnitEntity] { units.filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [UnitEntity] { units }
}

struct SelectUnitIntent: WidgetConfigurationIntent, SelectionIntent {
    static let title: LocalizedStringResource = "Stufe wählen"
    static let description = IntentDescription("Hat dein Kind nur eine Stufe, nimmt das Widget sie automatisch.")

    @Parameter(title: "Stufe") var unit: UnitEntity?

    var unitId: UUID? { unit.flatMap { UUID(uuidString: $0.id) } }
    var campId: UUID? { nil }
}

struct CampEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lager"
    static let defaultQuery = CampQuery()

    let id: String
    let title: String
    let range: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(range)") }
}

struct CampQuery: EntityQuery {
    private var camps: [CampEntity] {
        (WidgetStore.shared.read()?.camps ?? []).map { CampEntity(id: $0.id.uuidString, title: $0.title, range: WidgetFormat.campRange(from: $0.from, to: $0.to)) }
    }

    func entities(for identifiers: [String]) async throws -> [CampEntity] { camps.filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [CampEntity] { camps }
}

struct SelectCampIntent: WidgetConfigurationIntent, SelectionIntent {
    static let title: LocalizedStringResource = "Lager wählen"
    static let description = IntentDescription("Bist du nur in einem aktiven Lager, nimmt das Widget es automatisch.")

    @Parameter(title: "Lager") var camp: CampEntity?

    var unitId: UUID? { nil }
    var campId: UUID? { camp.flatMap { UUID(uuidString: $0.id) } }
}
