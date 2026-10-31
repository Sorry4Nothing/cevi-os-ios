import SwiftUI

/// Design tokens of "Cevi OS iOS" (style "Nachthimmel"). Spacing, corner radii, sizes and title fonts live here;
/// colors live in the asset catalog (`Color.cevi…`). Nothing of this is repeated in views.
enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
}

/// Corner radii. Always continuous corners: use `Radius.shape(_:)`.
enum Radius {
    /// Text fields, date tile.
    static let sm: CGFloat = 12
    /// Cards, list groups, banners.
    static let md: CGFloat = 16
    /// Chat bubbles.
    static let lg: CGFloat = 20
    /// Sign-in panel.
    static let xl: CGFloat = 28

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

enum Size {
    /// Minimum size of every control (HIG).
    static let touchTarget: CGFloat = 44
    /// Primary button height.
    static let button: CGFloat = 52
    static let field: CGFloat = 50
    static let avatar: CGFloat = 44
    /// Icon circle of the state screens (empty, offline, error …).
    static let stateIcon: CGFloat = 88
    /// Border of text fields; focused fields get `focusBorder`.
    static let border: CGFloat = 1
    static let focusBorder: CGFloat = 2
    /// Content never gets wider than this, so iPad and large windows stay readable.
    static let contentMax: CGFloat = 640
}

/// Title styles in Archivo (weight 800, card title 700). They grow with Dynamic Type relative to a system text style.
/// Everything else uses the system text styles (`.body`, `.subheadline` …).
enum TitleStyle {
    case display, largeTitle, title1, title2, day, cardTitle

    var size: CGFloat {
        switch self {
        case .display: 40
        case .largeTitle: 34
        case .title1: 28
        case .title2: 22
        case .day: 26
        case .cardTitle: 17
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .display, .largeTitle: .largeTitle
        case .title1: .title
        case .title2, .day: .title2
        case .cardTitle: .headline
        }
    }

    var weight: Font.Weight { self == .cardTitle ? .bold : .heavy }
}

extension Font {
    /// Archivo title font, e.g. `.font(.title(.largeTitle))`.
    static func title(_ style: TitleStyle) -> Font {
        .custom("Archivo", size: style.size, relativeTo: style.textStyle).weight(style.weight)
    }
}

extension View {
    /// Screen background: the `surface` color behind navigation and tab bar.
    func ceviScreenBackground() -> some View {
        background(Color.ceviSurface.ignoresSafeArea())
    }

    /// Card: `surface-container-low`, radius md, no shadow.
    func ceviCard(padding: CGFloat = Spacing.s4) -> some View {
        self.padding(padding)
            .background(Color.ceviSurfaceContainerLow, in: Radius.shape(Radius.md))
    }
}
