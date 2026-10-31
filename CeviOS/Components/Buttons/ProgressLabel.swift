import SwiftUI

/// Label of a main button with a spinner while the action runs.
struct ProgressLabel: View {
    let title: LocalizedStringKey
    let isRunning: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Text(title)
            if isRunning { ProgressView().tint(Color.ceviOnSurfaceVariant) }
        }
    }
}
