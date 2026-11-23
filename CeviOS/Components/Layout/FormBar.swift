import SwiftUI

extension View {
    /// Form screens (K1, K2, K4): no tab bar, the one main action in a fixed bar at the bottom.
    func formBar(_ title: LocalizedStringKey, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: action) { Text(title) }
                    .buttonStyle(.ceviPrimary)
                    .disabled(!isEnabled)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s3)
                    .frame(maxWidth: .infinity)
                    .background(Color.ceviSurface)
                    .overlay(alignment: .top) { Rectangle().fill(Color.ceviOutlineVariant).frame(height: Size.border) }
            }
    }

    /// After sending: the bar carries the secondary way out instead of the main action.
    func resultBar(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: action) { Text(title) }
                    .buttonStyle(CeviSecondaryButtonStyle())
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s3)
                    .frame(maxWidth: .infinity)
                    .background(Color.ceviSurface)
                    .overlay(alignment: .top) { Rectangle().fill(Color.ceviOutlineVariant).frame(height: Size.border) }
            }
    }
}

/// Outlined capsule for the secondary way out of a result.
struct CeviSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ceviOnSurface)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            .frame(maxWidth: .infinity, minHeight: Size.button)
            .overlay { Capsule().strokeBorder(Color.ceviOutline, lineWidth: Size.border) }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? pressedOpacity : 1)
    }
}
