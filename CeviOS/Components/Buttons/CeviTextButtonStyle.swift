import SwiftUI

/// Quiet text action in accent blue (e.g. «Abbrechen», «Zu den Programmen»).
struct CeviTextButtonStyle: ButtonStyle {
    var color: Color = .ceviAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.s3)
            .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == CeviTextButtonStyle {
    static var ceviText: CeviTextButtonStyle { CeviTextButtonStyle() }
}
