import SwiftUI

/// Label above a bordered text field. The field itself carries the accessibility label.
/// A tap anywhere in the box focuses the field, so the tap area is the whole box, not only the line of text.
struct CeviField<Field: View>: View {
    let label: LocalizedStringKey
    var focus: FocusState<Bool>.Binding?
    @ViewBuilder var field: Field

    private var isFocused: Bool { focus?.wrappedValue ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ceviOnSurfaceVariant)
                .accessibilityHidden(true)
            field
                .font(.body)
                .foregroundStyle(Color.ceviOnSurface)
                .padding(.leading, Spacing.s4)
                .padding(.trailing, Spacing.s1)
                .frame(maxWidth: .infinity, minHeight: Size.field, alignment: .leading)
                .background(Color.ceviSurface, in: Radius.shape(Radius.sm))
                .overlay {
                    Radius.shape(Radius.sm).strokeBorder(
                        isFocused ? Color.ceviFocus : Color.ceviOutline,
                        lineWidth: isFocused ? Size.focusBorder : Size.border
                    )
                }
                .contentShape(Radius.shape(Radius.sm))
                .simultaneousGesture(TapGesture().onEnded { focus?.wrappedValue = true })
        }
    }
}

#Preview("Bausteine") {
    @Previewable @State var text = "m.keller"
    @Previewable @State var password = "sternennacht"
    @Previewable @State var accepted = true
    @Previewable @FocusState var focused: Bool
    VStack(spacing: Spacing.s4) {
        Eyebrow("Cevi Stäfa-Hombrechtikon")
        CeviField(label: "Benutzername") { TextField("", text: $text) }
        CeviField(label: "Passwort", focus: $focused) {
            PasswordField(label: "Passwort", text: $password, isFocused: $focused)
        }
        Toggle("Ich habe die Datenschutzerklärung gelesen und zur Kenntnis genommen.", isOn: $accepted)
            .toggleStyle(CheckboxToggleStyle())
        Button("Anmelden") {}.buttonStyle(.ceviPrimary)
        Button("Anmelden") {}.buttonStyle(.ceviPrimary).disabled(true)
        Button("Abbrechen") {}.buttonStyle(.ceviText)
    }
    .padding(Spacing.s4)
    .ceviScreenBackground()
}
