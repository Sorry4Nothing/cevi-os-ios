import SwiftUI

/// Card of one program in «Mein Kalender» (A1, A2): time, title, place, group chips and what the children answered.
struct ProgramRow: View {
    let program: Program
    let day: Date

    var body: some View {
        content
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: Size.touchTarget, alignment: .leading)
            .ceviCard()
            .contentShape(Radius.shape(Radius.md))
            .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(ProgramFormat.time(of: program, on: day))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ceviAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(program.title)
                .font(.title(.cardTitle))
                .foregroundStyle(Color.ceviOnSurface)
                .strikethrough(program.status == .cancelled)
            if let place = program.place, !place.isEmpty {
                Text(place).font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            ProgramStatusLabel(status: program.status)
            TagChips(names: program.units.map(\.name) + program.otherTags.map(\.name))
            ForEach(ProgramAnswerSummary.lines(for: program.children), id: \.self) { line in
                AnswerSummaryLabel(line: line).font(.subheadline.weight(.semibold))
            }
            if let occasion = program.occasion, occasion.isOpen {
                Label(occasion.isRegistered ? "Angemeldet" : "Anmeldung offen", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
        }
    }
}

/// Group names as small chips (unit, team, function). Wrap at large text sizes.
struct TagChips: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            FlowLayout(spacing: Spacing.s2) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ceviOnSecondaryContainer)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s1)
                        .background(Color.ceviSecondaryContainer, in: Capsule())
                }
            }
        }
    }
}

/// One status line under a card: what the children answered, without names.
nonisolated enum ProgramAnswerSummary {
    enum Line: Hashable {
        case open(Int)
        case declined(Int)
        case allYes(Int)
    }

    static func lines(for children: [ProgramChild]) -> [Line] {
        guard !children.isEmpty else { return [] }
        let open = children.filter { $0.answer == nil }.count
        let declined = children.filter { $0.answer == .no }.count
        var lines: [Line] = []
        if open > 0 { lines.append(.open(open)) }
        if declined > 0 { lines.append(.declined(declined)) }
        if open == 0, declined == 0 { lines.append(.allYes(children.count)) }
        return lines
    }
}

/// The line with symbol and word, not color alone.
struct AnswerSummaryLabel: View {
    let line: ProgramAnswerSummary.Line

    var body: some View {
        switch line {
        case .open(let count):
            Label(count == 1 ? "Zusage für 1 Kind offen" : "Zusage für \(count) Kinder offen", systemImage: "questionmark.circle")
                .foregroundStyle(Color.ceviOnSurfaceVariant)
        case .declined(let count):
            Label(count == 1 ? "1 Kind hat abgesagt" : "\(count) Kinder haben abgesagt", systemImage: "xmark")
                .foregroundStyle(Color.ceviOnErrorContainer)
        case .allYes(let count):
            Label(count == 1 ? "Dein Kind hat zugesagt" : "Alle Kinder haben zugesagt", systemImage: "checkmark")
                .foregroundStyle(Color.ceviOnSuccessContainer)
        }
    }
}
