import SwiftUI

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
