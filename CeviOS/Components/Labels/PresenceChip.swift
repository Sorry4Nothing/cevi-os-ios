import SwiftUI

/// Recorded presence as chip: symbol and word.
struct PresenceChip: View {
    let presence: Presence?

    var body: some View {
        let (title, symbol, foreground, background): (LocalizedStringKey, String, Color, Color) = switch presence {
        case .present: ("Da", "checkmark", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .absent: ("Nicht da", "xmark", .ceviOnErrorContainer, .ceviErrorContainer)
        case nil: ("Nicht erfasst", "circle.dashed", .ceviOnSurfaceVariant, .clear)
        }
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
            .overlay { if presence == nil { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) } }
    }
}
