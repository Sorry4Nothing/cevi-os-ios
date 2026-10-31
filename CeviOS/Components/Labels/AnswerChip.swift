import SwiftUI

/// Answer as chip: symbol and word, never color alone.
struct AnswerChip: View {
    let answer: OverviewAnswer

    var body: some View {
        let (title, symbol, foreground, background): (LocalizedStringKey, String, Color, Color) = switch answer {
        case .yes: ("Ja", "checkmark", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .no: ("Nein", "xmark", .ceviOnErrorContainer, .ceviErrorContainer)
        case .open: ("Offen", "circle.dashed", .ceviOnSurfaceVariant, .clear)
        }
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
            .overlay {
                if answer == .open { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) }
            }
    }
}
