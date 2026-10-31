import SwiftUI

/// The one main action of a screen: Cevi-Rot capsule, at least `Size.button` high.
struct CeviPrimaryButtonStyle: ButtonStyle {
    /// Full width (forms) or as wide as the label (state screens).
    var expands = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            // Disabled: muted surface instead of a faded red, so the text keeps its contrast.
            .foregroundStyle(isEnabled ? Color.ceviOnPrimary : Color.ceviOnSurfaceVariant)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: Size.button)
            .background(isEnabled ? Color.ceviPrimary : Color.ceviSurfaceContainerHigh, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == CeviPrimaryButtonStyle {
    static var ceviPrimary: CeviPrimaryButtonStyle { CeviPrimaryButtonStyle() }
}
