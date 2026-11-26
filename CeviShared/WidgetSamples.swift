import Foundation

/// Invented data for previews, the widget gallery and tests. No real names.
nonisolated enum WidgetSamples {
    static func date(_ day: Int, _ month: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    static let unitId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let campId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    /// «Samstag, 14. November», 18:02.
    static let now = date(14, 11, 18, 2)

    static func snapshot(updatedAt: Date = now) -> WidgetSnapshot {
        WidgetSnapshot(
            session: .signedIn, updatedAt: updatedAt,
            units: [WidgetUnit(
                id: unitId, name: "Wölfe", isChildUnit: true,
                programs: [
                    WidgetProgram(id: UUID(), title: "Waldspiel", start: date(14, 11, 14), end: date(14, 11, 17), isAllDay: false, place: "Pfadiheim Beispielwald, Eingang Nord"),
                    WidgetProgram(id: UUID(), title: "Spielnachmittag", start: date(21, 11, 13, 30), end: nil, isAllDay: false, place: nil),
                    WidgetProgram(id: UUID(), title: "Kochen über dem Feuer", start: date(28, 11, 14), end: nil, isAllDay: false, place: nil),
                ],
                openAnswers: 1
            )],
            events: [
                WidgetEvent(id: UUID(), title: "Waldspiel", start: date(14, 11, 14), isAllDay: false, groups: ["Wölfe"]),
                WidgetEvent(id: UUID(), title: "Materialtag", start: date(21, 11, 9), isAllDay: false, groups: ["Team Mat"]),
                WidgetEvent(id: UUID(), title: "Spielnachmittag", start: date(21, 11, 13, 30), isAllDay: false, groups: ["Wölfe"]),
                WidgetEvent(id: UUID(), title: "Elternabend Sommerlager", start: date(25, 11, 19, 30), isAllDay: false, groups: ["Wölfe", "Adler"]),
                WidgetEvent(id: UUID(), title: "Waldweihnacht", start: date(28, 11, 16), isAllDay: false, groups: ["Wölfe", "Adler"]),
            ],
            camps: [WidgetCamp(
                id: campId, title: "Sommerlager Beispiel 2026", from: date(12, 11, 0), to: date(19, 11, 0),
                duty: WidgetDuty(name: "Küche", time: "07:00–10:00"),
                important: ["Abfahrt zum Waldspiel um 13:30", "Wölfe bringen Taschenlampen mit"],
                todosOpen: 1, todosTotal: 3, overdueCount: 2,
                tasks: [
                    WidgetTask(id: UUID(), title: "Offerte Lagerhaus einholen", due: date(15, 3, 0), isOverdue: true),
                    WidgetTask(id: UUID(), title: "Zelte zählen", due: date(16, 3, 0), isOverdue: true),
                    WidgetTask(id: UUID(), title: "Packliste prüfen", due: date(22, 3, 0), isOverdue: false),
                ],
                laterCount: 4, doneThisWeek: 5
            )],
            chat: WidgetChat(unread: 3, chats: 2)
        )
    }
}
