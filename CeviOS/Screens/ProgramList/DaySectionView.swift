import SwiftUI

/// One day of the timeline: weekday and day number on the left, the program cards on the right.
/// At accessibility text sizes the day moves above the cards.
struct DaySectionView: View {
    let section: ProgramListModel.DaySection
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Layout switch instead of `if`: the texts keep their identity when the text size changes.
        let isLarge = typeSize.isAccessibilitySize
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.s3))
        let dayLayout = isLarge
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s2))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            dayLayout {
                weekday
                dayNumber
                if !isLarge {
                    Capsule()
                        .fill(Color.ceviOutlineVariant)
                        .frame(width: Size.focusBorder)
                        .padding(.vertical, Spacing.s1)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: !isLarge, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ProgramFormat.fullDate(section.day)))
            .accessibilityAddTraits(.isHeader)
            cards
        }
    }

    private var weekday: some View {
        Text(ProgramFormat.weekday(section.day))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.ceviAccent)
    }

    private var dayNumber: some View {
        Text(section.day, format: .dateTime.day().locale(Locale(identifier: "de_CH")))
            .font(.title(.day))
            .foregroundStyle(Color.ceviOnSurface)
    }

    private var cards: some View {
        VStack(spacing: Spacing.s2) {
            ForEach(section.programs) { program in
                NavigationLink(value: program.id) { ProgramRow(program: program, day: section.day) }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Programmkarte") {
    let day = DateFormats.calendar.startOfDay(for: .now)
    let program = Program(id: UUID(), title: "Waldweihnacht vorbereiten", status: .active, visibility: .parents, isAllDay: false,
                          start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(17 * 3600), dayFrom: nil, dayTo: nil,
                          location: "Gemeindehaus", units: [UnitRef(id: UUID(), name: "Jungschar")], description: nil,
                          children: [ProgramChild(id: UUID(), firstName: "Lena", answer: nil),
                                     ProgramChild(id: UUID(), firstName: "Noah", answer: .yes)],
                          meetingPoint: nil, closingPlace: nil, closingTime: nil, bring: nil, isRegistrationOpen: nil, ownRegistration: nil)
    NavigationStack {
        ScrollView {
            DaySectionView(section: .init(day: day, programs: [program])).padding(Spacing.s4)
        }
        .ceviScreenBackground()
    }
}
