import SwiftUI

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
