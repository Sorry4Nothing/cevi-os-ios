import SwiftUI

/// Yes/No capsules. The chosen answer is filled, bold and has a check mark plus the selected trait, not color alone.
struct AnswerButtons: View {
    let name: String
    let selected: Answer?
    let disabled: Bool
    let onSelect: (Answer) -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            button(.yes, "Ja")
            button(.no, "Nein")
        }
    }

    private func button(_ answer: Answer, _ title: LocalizedStringKey) -> some View {
        let isSelected = selected == answer
        return Button { onSelect(answer) } label: {
            HStack(spacing: Spacing.s1) {
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(title)
            }
        }
        .buttonStyle(AnswerCapsuleStyle(answer: answer, isSelected: isSelected))
        .disabled(disabled)
        .accessibilityLabel(Text("\(name), \(title)"))
        // Voice Control: the visible word works as well as name plus word.
        .accessibilityInputLabels([Text(title), Text("\(name) \(title)")])
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AnswerCapsuleStyle: ButtonStyle {
    let answer: Answer
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isSelected ? .body.weight(.bold) : .body.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s4)
            .frame(minWidth: Size.touchTarget, minHeight: Size.touchTarget)
            .background(isSelected ? fill : Color.clear, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? foreground : Color.ceviOutline,
                                       lineWidth: isSelected ? Size.focusBorder : Size.border)
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? pressedOpacity : 1)
    }

    private var foreground: Color {
        guard isEnabled else { return .ceviOnSurfaceVariant }
        guard isSelected else { return .ceviOnSurface }
        return answer == .yes ? .ceviOnSuccessContainer : .ceviOnErrorContainer
    }

    private var fill: Color { answer == .yes ? .ceviSuccessContainer : .ceviErrorContainer }
}

#Preview("Antworten") {
    VStack(alignment: .leading, spacing: Spacing.s4) {
        AnswerButtons(name: "Lena", selected: nil, disabled: false) { _ in }
        AnswerButtons(name: "Noah", selected: .yes, disabled: false) { _ in }
        AnswerButtons(name: "Mia", selected: .no, disabled: true) { _ in }
    }
    .padding(Spacing.s4)
    .ceviScreenBackground()
}
