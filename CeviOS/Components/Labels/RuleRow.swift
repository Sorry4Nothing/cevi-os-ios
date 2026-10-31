import SwiftUI

/// Fulfilled or open rule, with symbol and word (not color alone).
struct RuleRow: View {
    let text: LocalizedStringKey
    let isMet: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
        }
        .font(.subheadline)
        .foregroundStyle(isMet ? Color.ceviOnSuccessContainer : Color.ceviOnSurfaceVariant)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        // Status in the label, not as a value: a value makes the audit treat the row as a control.
        .accessibilityLabel(Text(text) + Text(isMet ? ", erfüllt" : ", nicht erfüllt"))
        .accessibilityAddTraits(.isStaticText)
    }
}
