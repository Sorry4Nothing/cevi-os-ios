import SwiftUI

/// Banner with a symbol, a bold first line and a text. Info, success or error; the meaning is in words and symbol.
struct InfoBanner<Trailing: View>: View {
    enum Tone { case info, success, error }

    let tone: Tone
    let title: String
    var message: String?
    @ViewBuilder var trailing: Trailing

    private var symbol: String {
        switch tone {
        case .info: "info.circle"
        case .success: "checkmark"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var foreground: Color {
        switch tone {
        case .info: .ceviOnSecondaryContainer
        case .success: .ceviOnSuccessContainer
        case .error: .ceviOnErrorContainer
        }
    }

    private var background: Color {
        switch tone {
        case .info: .ceviSecondaryContainer
        case .success: .ceviSuccessContainer
        case .error: .ceviErrorContainer
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: symbol).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).fontWeight(.semibold)
                    if let message { Text(message) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .font(.callout)
        .foregroundStyle(foreground)
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: Radius.shape(Radius.md))
    }
}

extension InfoBanner where Trailing == EmptyView {
    init(tone: Tone, title: String, message: String? = nil) {
        self.init(tone: tone, title: title, message: message) { EmptyView() }
    }
}

/// Status chip of a suggestion or a room request: symbol and word in a capsule.
struct RequestStatusChip: View {
    enum Kind { case open, confirmed, declined, cancelled }

    let kind: Kind

    var body: some View {
        let (title, symbol, foreground, background): (LocalizedStringKey, String, Color, Color) = switch kind {
        case .open: ("Offen", "questionmark.circle", .ceviOnSurface, .clear)
        case .confirmed: ("Bestätigt", "checkmark", .ceviOnSuccessContainer, .ceviSuccessContainer)
        case .declined: ("Abgelehnt", "xmark", .ceviOnErrorContainer, .ceviErrorContainer)
        case .cancelled: ("Storniert", "minus.circle", .ceviOnSurfaceVariant, .clear)
        }
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
            .overlay { if background == .clear { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) } }
    }
}

/// Text below a field when its input is wrong. Symbol and words, not color alone.
struct FieldError: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Color.ceviOnErrorContainer)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
