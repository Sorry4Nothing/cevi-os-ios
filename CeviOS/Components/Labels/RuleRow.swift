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
        .accessibilityLabel(Text(text))
        .accessibilityValue(isMet ? Text("erfüllt") : Text("nicht erfüllt"))
    }
}
