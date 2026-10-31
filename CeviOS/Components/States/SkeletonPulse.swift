import SwiftUI

/// Slow pulse for skeleton placeholders. With "Reduce Motion" the placeholders stay still.
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { if !reduceMotion { dimmed = true } }
    }
}

extension View {
    func skeletonPulse() -> some View { modifier(SkeletonPulse()) }
}
