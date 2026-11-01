import SwiftUI

/// Status chip: symbol and word in a capsule, never only color. Nothing for a normal active program.
struct ProgramStatusLabel: View {
    let status: ProgramStatus

    var body: some View {
        switch status {
        case .active:
            EmptyView()
        case .cancelled:
            chip("Abgesagt", symbol: "xmark.octagon.fill", foreground: .ceviOnErrorContainer, background: .ceviErrorContainer)
        case .review:
            chip("Wird geprüft", symbol: "questionmark.circle.fill", foreground: .ceviOnWarningContainer, background: .ceviWarningContainer)
        }
    }

    private func chip(_ title: LocalizedStringKey, symbol: String, foreground: Color, background: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .background(background, in: Capsule())
    }
}
