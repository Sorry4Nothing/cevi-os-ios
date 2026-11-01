import SwiftUI

struct ProgramRow: View {
    let program: Program
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(([ProgramFormat.time(of: program, on: day)] + program.units.map(\.name)).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ceviAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(program.title)
                .font(.title(.cardTitle))
                .foregroundStyle(Color.ceviOnSurface)
                .strikethrough(program.status == .cancelled)
            if let location = program.location, !location.isEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            ProgramStatusLabel(status: program.status)
            ForEach(program.children) { child in
                AnswerLabel(name: child.firstName, answer: child.answer)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: Size.touchTarget, alignment: .leading)
        .ceviCard()
        .contentShape(Radius.shape(Radius.md))
        .accessibilityElement(children: .combine)
    }
}
