import SwiftUI

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
