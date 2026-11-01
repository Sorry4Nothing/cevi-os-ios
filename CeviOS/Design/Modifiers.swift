import SwiftUI

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
