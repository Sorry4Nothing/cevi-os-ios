import SwiftUI

/// Slow pulse for skeleton placeholders, at most 5 seconds (WCAG 2.2.2). With "Reduce Motion" the placeholders stay still.
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .task {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatCount(5, autoreverses: true)) { dimmed = true }
                try? await Task.sleep(for: .seconds(4.5))
                withAnimation(.easeInOut(duration: 0.3)) { dimmed = false }
            }
    }
}

extension View {
    func skeletonPulse() -> some View { modifier(SkeletonPulse()) }
}
