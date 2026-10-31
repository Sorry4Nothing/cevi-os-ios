import SwiftUI

/// Yes/No buttons. The chosen answer is marked by a filled button, a check mark and the selected trait, not by color alone.
struct AnswerButtons: View {
    let name: String
    let selected: Answer?
    let disabled: Bool
    let onSelect: (Answer) -> Void

    var body: some View {
        HStack {
            button(.yes, "Ja")
            button(.no, "Nein")
        }
    }

    private func button(_ answer: Answer, _ title: LocalizedStringKey) -> some View {
        let isSelected = selected == answer
        return Group {
            if isSelected {
                Button { onSelect(answer) } label: { label(title, selected: true) }.buttonStyle(.borderedProminent)
            } else {
                Button { onSelect(answer) } label: { label(title, selected: false) }.buttonStyle(.bordered)
            }
        }
        .disabled(disabled)
        .accessibilityLabel(Text("\(name): \(title)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func label(_ title: LocalizedStringKey, selected: Bool) -> some View {
        HStack {
            if selected { Image(systemName: "checkmark") }
            Text(title)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}
