import Foundation

/// The program screens read «Mein Kalender» (`GET /api/v1/termine/mein`, `…/{id}`). `Program` stays the model of those
/// screens: an event is a program with its unit tags and the answers of the person's children.
nonisolated extension Program {
    init(event: CalendarEvent) {
        self.init(
            id: event.id, title: event.title, status: event.status.programStatus, visibility: .parents, isAllDay: event.isAllDay,
            start: event.start, end: event.end, dayFrom: event.dayFrom, dayTo: event.dayTo,
            units: event.tags.filter { $0.kind == .unit }.map { UnitRef(id: $0.id, name: $0.name) },
            children: event.children.map { ProgramChild(id: $0.id, firstName: $0.firstName, answer: $0.answer) },
            meetingPoint: nil, closingPlace: nil, closingTime: nil, bring: nil, isRegistrationOpen: nil, ownRegistration: nil,
            place: event.place, otherTags: event.tags.filter { $0.kind != .unit }, occasion: event.occasion
        )
    }

    init(detail: CalendarEventDetail) {
        let base = Program(event: detail.event)
        self.init(
            id: base.id, title: base.title, status: base.status, visibility: base.visibility, isAllDay: base.isAllDay,
            start: base.start, end: base.end, dayFrom: base.dayFrom, dayTo: base.dayTo, units: base.units, children: base.children,
            meetingPoint: detail.meetingPoint, closingPlace: detail.endPlace, closingTime: detail.endTime, bring: detail.bring,
            isRegistrationOpen: detail.isParticipationOpen, ownRegistration: detail.ownRegistration.flatMap { OwnRegistration(rawValue: $0.rawValue) },
            place: base.place, otherTags: base.otherTags, occasion: base.occasion
        )
    }

}

nonisolated extension EventStatus {
    /// An unknown status never offers answers.
    var programStatus: ProgramStatus {
        switch self {
        case .active: .active
        case .cancelled: .cancelled
        case .check, .unknown: .review
        }
    }
}
